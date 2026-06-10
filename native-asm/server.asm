format PE GUI 4.0
entry start

include '..\tools\fasm\include\win32ax.inc'

AF_INET      = 2
SOCK_STREAM  = 1
SOCK_DGRAM   = 2
IPPROTO_TCP  = 6
IPPROTO_UDP  = 17
INVALID_SOCKET = -1
session_slots = 16

section '.text' code readable executable

start:
        invoke  WSAStartup,0202h,wsa_data

        invoke  socket,AF_INET,SOCK_DGRAM,IPPROTO_UDP
        mov     [osc_socket],eax
        invoke  htons,9000
        mov     word [osc_addr+2],ax
        invoke  inet_addr,localhost
        mov     dword [osc_addr+4],eax

        invoke  socket,AF_INET,SOCK_STREAM,IPPROTO_TCP
        mov     [server_socket],eax
        cmp     eax,INVALID_SOCKET
        je      exit

        invoke  htons,19001
        mov     word [server_addr+2],ax
        invoke  bind,[server_socket],server_addr,16
        cmp     eax,0
        jne     open_existing_and_exit
        invoke  setsockopt,[server_socket],0FFFFh,1006h,accept_timeout,4
        invoke  listen,[server_socket],8

        invoke  ShellExecute,0,open_action,url,0,0,1

accept_loop:
        call    cleanup_sessions
        mov     dword [readfds],1
        mov     eax,[server_socket]
        mov     [readfds+4],eax
        mov     dword [select_timeout],1
        mov     dword [select_timeout+4],0
        invoke  select,0,readfds,0,0,select_timeout
        cmp     eax,0
        jle     accept_loop
        invoke  accept,[server_socket],0,0
        cmp     eax,INVALID_SOCKET
        je      accept_loop

        mov     [client_socket],eax
        mov     dword [shutdown_pending],0
        invoke  setsockopt,[client_socket],0FFFFh,1006h,recv_timeout,4
        invoke  recv,[client_socket],recv_buf,recv_buf_size-1,0
        cmp     eax,0
        jle     close_client

        mov     [recv_len],eax
        mov     byte [recv_buf+eax],0

        call    is_post_send
        cmp     eax,1
        je      handle_send

        call    is_get_settings
        cmp     eax,1
        je      handle_get_settings

        call    is_post_settings
        cmp     eax,1
        je      handle_post_settings

        call    is_post_session_open
        cmp     eax,1
        je      handle_session_open

        call    is_post_session_close
        cmp     eax,1
        je      handle_session_close

        call    is_post_heartbeat
        cmp     eax,1
        je      handle_heartbeat

        call    is_get_lan_ip
        cmp     eax,1
        je      handle_lan_ip

        call    serve_index
        jmp     close_client

handle_send:
        call    find_body
        test    eax,eax
        jz      send_no_content

        mov     esi,eax
        mov     ecx,[recv_len]
        sub     ecx,esi
        add     ecx,recv_buf
        cmp     ecx,7900
        jle     .len_ok
        mov     ecx,7900

.len_ok:
        push    ecx
        push    esi
        call    send_osc

send_no_content:
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client

handle_get_settings:
        call    serve_settings
        jmp     close_client

handle_post_settings:
        call    find_body
        test    eax,eax
        jz      send_no_content

        mov     esi,eax
        mov     [body_ptr],esi
        call    parse_content_length
        mov     [content_len],eax
        mov     ecx,[recv_len]
        sub     ecx,[body_ptr]
        add     ecx,recv_buf
        mov     [body_have],ecx

.read_more_settings:
        mov     eax,[body_have]
        cmp     eax,[content_len]
        jge     .settings_len_ready
        mov     eax,recv_buf
        add     eax,[recv_len]
        invoke  recv,[client_socket],eax,recv_buf_size-1,0
        cmp     eax,0
        jle     .settings_len_ready
        add     [recv_len],eax
        add     [body_have],eax
        jmp     .read_more_settings

.settings_len_ready:
        mov     ecx,[content_len]
        cmp     ecx,settings_buf_size
        jle     .settings_len_ok
        mov     ecx,settings_buf_size

.settings_len_ok:
        mov     [settings_write_len],ecx
        invoke  CreateFile,settings_file,40000000h,0,0,2,80h,0
        cmp     eax,-1
        je      send_no_content
        mov     [settings_handle],eax
        invoke  WriteFile,[settings_handle],[body_ptr],[settings_write_len],bytes_done,0
        invoke  CloseHandle,[settings_handle]
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client

handle_session_open:
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client

handle_session_close:
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client

handle_lan_ip:
        call    serve_lan_ip
        jmp     close_client

handle_heartbeat:
        call    read_heartbeat_id
        test    eax,eax
        jz      .done
        call    upsert_session
.done:
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client

close_client:
        invoke  closesocket,[client_socket]
        jmp     accept_loop

exit:
        invoke  ExitProcess,0

open_existing_and_exit:
        invoke  ShellExecute,0,open_action,url,0,0,1
        invoke  closesocket,[server_socket]
        invoke  closesocket,[osc_socket]
        invoke  WSACleanup
        invoke  ExitProcess,0

shutdown_now:
        invoke  closesocket,[server_socket]
        invoke  closesocket,[osc_socket]
        invoke  WSACleanup
        invoke  ExitProcess,0

is_post_send:
        mov     esi,recv_buf
        mov     edi,post_send
        mov     ecx,post_send_len
        repe    cmpsb
        sete    al
        movzx   eax,al
        ret

is_get_settings:
        mov     esi,recv_buf
        mov     edi,get_settings
        mov     ecx,get_settings_len
        repe    cmpsb
        sete    al
        movzx   eax,al
        ret

is_post_settings:
        mov     esi,recv_buf
        mov     edi,post_settings
        mov     ecx,post_settings_len
        repe    cmpsb
        sete    al
        movzx   eax,al
        ret

is_post_session_open:
        mov     esi,recv_buf
        mov     edi,post_session_open
        mov     ecx,post_session_open_len
        repe    cmpsb
        sete    al
        movzx   eax,al
        ret

is_post_session_close:
        mov     esi,recv_buf
        mov     edi,post_session_close
        mov     ecx,post_session_close_len
        repe    cmpsb
        sete    al
        movzx   eax,al
        ret

is_post_heartbeat:
        mov     esi,recv_buf
        mov     edi,post_heartbeat
        mov     ecx,post_heartbeat_len
        repe    cmpsb
        sete    al
        movzx   eax,al
        ret

is_get_lan_ip:
        mov     esi,recv_buf
        mov     edi,get_lan_ip
        mov     ecx,get_lan_ip_len
        repe    cmpsb
        sete    al
        movzx   eax,al
        ret

read_heartbeat_id:
        mov     esi,recv_buf
        mov     ecx,[recv_len]
.scan:
        cmp     ecx,3
        jb      .not_found
        cmp     byte [esi],'i'
        jne     .next
        cmp     byte [esi+1],'d'
        jne     .next
        cmp     byte [esi+2],'='
        jne     .next
        add     esi,3
        mov     edi,current_id
        mov     ecx,31
.copy:
        mov     al,[esi]
        cmp     al,' '
        je      .done
        cmp     al,'&'
        je      .done
        cmp     al,13
        je      .done
        cmp     al,10
        je      .done
        test    al,al
        jz      .done
        stosb
        inc     esi
        loop    .copy
.done:
        mov     byte [edi],0
        mov     eax,current_id
        ret
.next:
        inc     esi
        dec     ecx
        jmp     .scan
.not_found:
        xor     eax,eax
        ret

upsert_session:
        mov     dword [ever_had_session],1
        invoke  GetTickCount
        mov     [now_tick],eax
        xor     ebx,ebx
.find_loop:
        cmp     ebx,session_slots
        jge     .insert
        mov     edi,sessions
        mov     eax,ebx
        shl     eax,5
        add     edi,eax
        cmp     byte [edi],0
        je      .next_find
        push    ebx
        push    edi
        mov     esi,current_id
        mov     ecx,32
        repe    cmpsb
        pop     edi
        pop     ebx
        je      .update
.next_find:
        inc     ebx
        jmp     .find_loop
.update:
        mov     eax,ebx
        shl     eax,2
        mov     edx,last_seen
        add     edx,eax
        mov     eax,[now_tick]
        mov     [edx],eax
        ret
.insert:
        xor     ebx,ebx
.insert_loop:
        cmp     ebx,session_slots
        jge     .done
        mov     edi,sessions
        mov     eax,ebx
        shl     eax,5
        add     edi,eax
        cmp     byte [edi],0
        je      .write
        inc     ebx
        jmp     .insert_loop
.write:
        mov     esi,current_id
        mov     ecx,32
        rep     movsb
        mov     eax,ebx
        shl     eax,2
        mov     edx,last_seen
        add     edx,eax
        mov     eax,[now_tick]
        mov     [edx],eax
.done:
        ret

cleanup_sessions:
        invoke  GetTickCount
        mov     [now_tick],eax
        xor     ebx,ebx
        xor     esi,esi
.loop:
        cmp     ebx,session_slots
        jge     .done
        mov     edi,sessions
        mov     eax,ebx
        shl     eax,5
        add     edi,eax
        cmp     byte [edi],0
        je      .next
        mov     eax,ebx
        shl     eax,2
        mov     edx,last_seen
        add     edx,eax
        mov     eax,[now_tick]
        sub     eax,[edx]
        cmp     eax,10000
        jbe     .active
        mov     byte [edi],0
        jmp     .next
.active:
        inc     esi
.next:
        inc     ebx
        jmp     .loop
.done:
        cmp     esi,0
        jne     .ret
        cmp     dword [ever_had_session],1
        jne     .ret
        jmp     shutdown_now
.ret:
        ret

find_body:
        mov     esi,recv_buf
        mov     ecx,[recv_len]
        sub     ecx,3
        jle     .not_found

.scan:
        cmp     dword [esi],0A0D0A0Dh
        je      .found
        inc     esi
        loop    .scan

.not_found:
        xor     eax,eax
        ret

.found:
        lea     eax,[esi+4]
        ret

parse_content_length:
        mov     esi,recv_buf
        mov     ecx,[recv_len]

.next:
        cmp     ecx,15
        jb      .zero
        push    esi
        mov     edi,content_length_header
        mov     edx,15

.cmp:
        mov     al,[esi]
        cmp     al,'a'
        jb      .case_ok
        cmp     al,'z'
        ja      .case_ok
        sub     al,32
.case_ok:
        cmp     al,[edi]
        jne     .no
        inc     esi
        inc     edi
        dec     edx
        jnz     .cmp
        pop     esi
        add     esi,15
        xor     eax,eax
.digits:
        mov     bl,[esi]
        cmp     bl,' '
        je      .skip
        cmp     bl,'0'
        jb      .done
        cmp     bl,'9'
        ja      .done
        imul    eax,eax,10
        sub     bl,'0'
        movzx   ebx,bl
        add     eax,ebx
.skip:
        inc     esi
        jmp     .digits
.done:
        ret

.no:
        pop     esi
        inc     esi
        dec     ecx
        jmp     .next

.zero:
        xor     eax,eax
        ret

serve_index:
        invoke  send,[client_socket],http_200_html,http_200_html_len,0
        invoke  send,[client_socket],html,html_len,0
        ret

serve_settings:
        invoke  CreateFile,settings_file,80000000h,1,0,3,80h,0
        cmp     eax,-1
        je      .empty
        mov     [settings_handle],eax
        invoke  ReadFile,[settings_handle],settings_buf,settings_buf_size,bytes_done,0
        invoke  CloseHandle,[settings_handle]
        invoke  send,[client_socket],http_200_json,http_200_json_len,0
        invoke  send,[client_socket],settings_buf,[bytes_done],0
        ret

.empty:
        invoke  send,[client_socket],http_200_json,http_200_json_len,0
        invoke  send,[client_socket],empty_json,empty_json_len,0
        ret

serve_lan_ip:
        call    find_host_lan_ip
        cmp     eax,1
        je      .send_best
        invoke  socket,AF_INET,SOCK_DGRAM,IPPROTO_UDP
        mov     [tmp_socket],eax
        cmp     eax,INVALID_SOCKET
        je      .fallback
        invoke  htons,80
        mov     word [tmp_addr+2],ax
        invoke  inet_addr,dns_probe_ip
        mov     dword [tmp_addr+4],eax
        invoke  connect,[tmp_socket],tmp_addr,16
        mov     dword [sockaddr_len],16
        invoke  getsockname,[tmp_socket],local_addr,sockaddr_len
        invoke  closesocket,[tmp_socket]
        cmp     eax,0
        jne     .fallback
        invoke  inet_ntoa,dword [local_addr+4]
        test    eax,eax
        jz      .fallback
        mov     esi,eax
        call    send_lan_json
        ret
.send_best:
        mov     esi,best_ip
        call    send_lan_json
        ret
.fallback:
        invoke  send,[client_socket],http_200_json,http_200_json_len,0
        invoke  send,[client_socket],lan_fallback_json,lan_fallback_json_len,0
        ret

find_host_lan_ip:
        mov     dword [best_ip_score],0
        invoke  gethostname,hostname,255
        cmp     eax,0
        jne     .not_found
        invoke  gethostbyname,hostname
        test    eax,eax
        jz      .not_found
        mov     ebx,eax
        mov     edi,[ebx+12]
        test    edi,edi
        jz      .not_found
.next_addr:
        mov     ebx,[edi]
        test    ebx,ebx
        jz      .done
        invoke  inet_ntoa,dword [ebx]
        test    eax,eax
        jz      .advance
        mov     esi,eax
        call    score_ip
        cmp     eax,[best_ip_score]
        jle     .advance
        mov     [best_ip_score],eax
        mov     [hlist_ptr],edi
        mov     edi,best_ip
        mov     ecx,15
.copy_best:
        lodsb
        stosb
        test    al,al
        jz      .copied
        loop    .copy_best
        mov     byte [edi],0
.copied:
        mov     edi,[hlist_ptr]
        cmp     dword [best_ip_score],3
        je      .done
.advance:
        add     edi,4
        jmp     .next_addr
.done:
        cmp     dword [best_ip_score],0
        jg      .found
.not_found:
        xor     eax,eax
        ret
.found:
        mov     eax,1
        ret

score_ip:
        cmp     byte [esi],'1'
        jne     .not_1
        cmp     byte [esi+1],'9'
        jne     .check_10
        cmp     byte [esi+2],'2'
        jne     .zero
        cmp     byte [esi+3],'.'
        jne     .zero
        cmp     byte [esi+4],'1'
        jne     .zero
        cmp     byte [esi+5],'6'
        jne     .zero
        cmp     byte [esi+6],'8'
        jne     .zero
        cmp     byte [esi+7],'.'
        jne     .zero
        mov     eax,3
        ret
.check_10:
        cmp     byte [esi+1],'0'
        jne     .check_172
        cmp     byte [esi+2],'.'
        jne     .check_172
        mov     eax,2
        ret
.check_172:
        cmp     byte [esi+1],'7'
        jne     .zero
        cmp     byte [esi+2],'2'
        jne     .zero
        cmp     byte [esi+3],'.'
        jne     .zero
        lea     edi,[esi+4]
        call    parse_octet
        cmp     eax,16
        jb      .zero
        cmp     eax,31
        ja      .zero
        mov     eax,1
        ret
.not_1:
        jmp     .zero
.zero:
        xor     eax,eax
        ret

parse_octet:
        xor     eax,eax
        xor     ecx,ecx
.loop:
        mov     bl,[edi]
        cmp     bl,'0'
        jb      .done
        cmp     bl,'9'
        ja      .done
        imul    eax,eax,10
        sub     bl,'0'
        movzx   ebx,bl
        add     eax,ebx
        inc     edi
        inc     ecx
        cmp     ecx,3
        jb      .loop
.done:
        ret

send_lan_json:
        mov     edi,lan_json+7
        mov     ecx,15
.copy_ip:
        lodsb
        stosb
        test    al,al
        jz      .ip_done
        loop    .copy_ip
        mov     byte [edi],0
.ip_done:
        dec     edi
        mov     esi,lan_json_tail
        mov     ecx,lan_json_tail_len
        rep     movsb
        mov     eax,edi
        sub     eax,lan_json
        mov     [lan_json_len],eax
        invoke  send,[client_socket],http_200_json,http_200_json_len,0
        invoke  send,[client_socket],lan_json,[lan_json_len],0
        ret

send_osc:
        push    ebp
        mov     ebp,esp
        mov     esi,[ebp+8]
        mov     ebx,[ebp+12]
        mov     edi,osc_packet

        mov     esi,osc_addr_text
        mov     ecx,osc_addr_text_len
        call    write_osc_string

        mov     esi,osc_types
        mov     ecx,osc_types_len
        call    write_osc_string

        mov     esi,[ebp+8]
        mov     ecx,ebx
        call    write_osc_string

        mov     eax,edi
        sub     eax,osc_packet
        invoke  sendto,[osc_socket],osc_packet,eax,0,osc_addr,16
        pop     ebp
        ret     8

write_osc_string:
        push    ecx
        rep     movsb
        mov     byte [edi],0
        inc     edi
        pop     ecx
        inc     ecx

.pad:
        test    ecx,3
        jz      .done
        mov     byte [edi],0
        inc     edi
        inc     ecx
        jmp     .pad

.done:
        ret

section '.data' data readable writeable

localhost db '127.0.0.1',0
open_action db 'open',0
url db 'http://127.0.0.1:19001',0

post_send db 'POST /send '
post_send_len = $ - post_send
get_settings db 'GET /settings '
get_settings_len = $ - get_settings
post_settings db 'POST /settings '
post_settings_len = $ - post_settings
post_session_open db 'POST /session/open '
post_session_open_len = $ - post_session_open
post_session_close db 'POST /session/close '
post_session_close_len = $ - post_session_close
post_heartbeat db 'POST /heartbeat'
post_heartbeat_len = $ - post_heartbeat
get_lan_ip db 'GET /lan-ip '
get_lan_ip_len = $ - get_lan_ip
content_length_header db 'CONTENT-LENGTH:'
settings_file db 'settings.json',0
dns_probe_ip db '8.8.8.8',0

http_200_html db 'HTTP/1.1 200 OK',13,10
              db 'Connection: close',13,10
              db 'Content-Type: text/html; charset=utf-8',13,10,13,10
http_200_html_len = $ - http_200_html

http_200_json db 'HTTP/1.1 200 OK',13,10
              db 'Connection: close',13,10
              db 'Content-Type: application/json; charset=utf-8',13,10,13,10
http_200_json_len = $ - http_200_json

http_204 db 'HTTP/1.1 204 No Content',13,10
         db 'Connection: close',13,10
         db 'Content-Length: 0',13,10,13,10
http_204_len = $ - http_204

empty_json db '{}'
empty_json_len = $ - empty_json
lan_fallback_json db '{"ip":"127.0.0.1"}'
lan_fallback_json_len = $ - lan_fallback_json
lan_json db '{"ip":"'
         rb 16
lan_json_tail db '"}'
lan_json_tail_len = $ - lan_json_tail
lan_json_len dd 0

osc_addr_text db '/chatbox/input'
osc_addr_text_len = $ - osc_addr_text
osc_types db ',sT'
osc_types_len = $ - osc_types

html db '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VRC Chatbox OSC</title><style>'
     db '*{box-sizing:border-box}body{margin:0;min-height:100dvh;display:grid;place-items:center;background:#f4f6f8;color:#111827;font-family:Segoe UI,system-ui,sans-serif;padding:24px}'
     db 'main{width:min(760px,100%);background:white;border:1px solid #d8dee8;border-radius:8px;box-shadow:0 18px 60px rgb(15 23 42/.10);overflow:hidden}'
     db 'header{display:flex;justify-content:space-between;gap:16px;padding:18px 20px;border-bottom:1px solid #d8dee8}h1{font-size:18px;margin:0}.s{color:#667085;font-size:13px}.s:before{content:"";display:inline-block;width:8px;height:8px;border-radius:99px;background:#0f766e;margin-right:8px}'
     db '.c{padding:20px}textarea{width:100%;min-height:260px;resize:vertical;border:1px solid #d8dee8;border-radius:8px;padding:16px;background:#fbfcfe;color:#111827;font:inherit;font-size:18px;line-height:1.55;outline:0}textarea:focus{border-color:#0f766e;box-shadow:0 0 0 3px rgb(15 118 110/.16)}'
     db '.row{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-bottom:12px}.row2{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px}.row3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-bottom:12px}select,input{width:100%;border:1px solid #d8dee8;border-radius:8px;padding:10px;background:#fbfcfe;color:#111827}label{display:block;color:#667085;font-size:12px;margin:0 0 5px}.lan{display:flex;justify-content:space-between;gap:12px;align-items:center;padding:10px 12px;border:1px solid #d8dee8;border-radius:8px;margin-bottom:12px;background:#fbfcfe}.lan b{font-size:13px}.lan code{font-size:13px;color:#115e59}.a{display:flex;align-items:center;justify-content:space-between;gap:14px;margin-top:14px}.h,.m,.warn{color:#667085;font-size:13px}.warn{padding:10px;border:1px solid #fecdca;background:#fff5f4;color:#b42318;border-radius:8px;margin:0 0 12px}.hide{display:none}.linkbtn{display:flex;align-items:center;justify-content:center;border-radius:8px;padding:10px 12px;background:#eef8f6;color:#115e59;text-decoration:none;font-size:13px;font-weight:650}button{min-width:132px;border:0;border-radius:8px;padding:12px 18px;background:#0f766e;color:white;font:inherit;font-weight:650;cursor:pointer}button:hover{background:#115e59}button:active{transform:translateY(1px)}button:disabled{cursor:wait;opacity:.72}.e{color:#b42318}@media(max-width:560px){body{padding:12px}header,.a,.row,.row2,.row3,.lan{align-items:stretch;grid-template-columns:1fr;flex-direction:column}button{width:100%}}</style></head>'
     db '<body><main><header><h1>VRC Chatbox OSC</h1><div class="s" id="status">本地服务已连接</div></header><section class="c"><div class="lan"><b>局域网访问地址</b><code id="lan">正在检测...</code></div><div class="row3"><div><label>源语言</label><select id="src"><option value="zh-CN">简体中文</option><option value="en">English</option><option value="ja">日本語</option><option value="ko">한국어</option><option value="fr">Français</option><option value="de">Deutsch</option><option value="es">Español</option></select></div><div><label>目标语言</label><select id="dst"><option value="en">English</option><option value="zh-CN">简体中文</option><option value="ja">日本語</option><option value="ko">한국어</option><option value="fr">Français</option><option value="de">Deutsch</option><option value="es">Español</option></select></div><div><label>翻译服务</label><select id="provider"><option value="mymemory">MyMemory 免费公开 API</option><option value="openai">ChatGPT / OpenAI</option><option value="deepseek">DeepSeek</option><option value="hunyuan">腾讯混元</option><option value="custom">自定义 OpenAI 兼容 API</option></select></div></div><div class="warn">Key 会保存到本机 settings.json。不要把这个文件复制或发送给任何人。若 MyMemory 翻译失败或提示额度不足，请尝试填写 email，或自行获取 key 后使用。</div><div id="mmBox" class="row"><input id="mmEmail" placeholder="MyMemory email，可提升免费额度"><input id="mmKey" placeholder="MyMemory key，可选"><a class="linkbtn" target="_blank" href="https://mymemory.translated.net/doc/keygen.php">获取 MyMemory key</a></div><div id="aiBox" class="row hide"><input id="endpoint" placeholder="AI Base URL，例如 https://api.openai.com/v1"><input id="model" placeholder="模型，例如 gpt-4o-mini / deepseek-chat"><input id="key" placeholder="AI API Key"></div><textarea id="text" autofocus placeholder="输入源语言。发送时会自动翻译，并把译文换行拼接到源语言后面。"></textarea><div class="a"><div class="h">Enter 翻译并发送，Ctrl + Enter 换行</div><button id="button" type="button">翻译发送</button></div><div class="m" id="message"></div></section></main>'
     db '<script>const $=id=>document.getElementById(id),b=$("button"),t=$("text"),m=$("message"),s=$("status"),lan=$("lan"),src=$("src"),dst=$("dst"),p=$("provider"),ep=$("endpoint"),model=$("model"),key=$("key"),mmEmail=$("mmEmail"),mmKey=$("mmKey"),mmBox=$("mmBox"),aiBox=$("aiBox");let timer=0;const sid=(Date.now().toString(36)+Math.random().toString(36).slice(2,10)).slice(0,31);function beat(){fetch("/heartbeat?id="+encodeURIComponent(sid),{method:"POST"}).catch(()=>{})}beat();setInterval(beat,3000);fetch("/lan-ip").then(r=>r.json()).then(j=>lan.textContent="http://"+j.ip+":19001").catch(()=>lan.textContent="http://本机局域网IP:19001");function showBoxes(){let mm=p.value==="mymemory";mmBox.className=mm?"row":"row hide";aiBox.className=mm?"row hide":"row"}function preset(force){const ps={openai:["https://api.openai.com/v1","gpt-4o-mini"],deepseek:["https://api.deepseek.com","deepseek-chat"],hunyuan:["https://api.hunyuan.cloud.tencent.com/v1","hunyuan-turbos-latest"]}[p.value];if(!ps)return;if(force||!ep.value)ep.value=ps[0];if(force||!model.value)model.value=ps[1]}async function load(){try{const r=await fetch("/settings");const j=await r.json();src.value=j.src||src.value;dst.value=j.dst||dst.value;p.value=j.provider||p.value;ep.value=j.endpoint||"";model.value=j.model||"";key.value=j.key||"";mmEmail.value=j.mmEmail||"";mmKey.value=j.mmKey||"";preset(false);showBoxes()}catch(e){showBoxes()}}async function save(){const j={src:src.value,dst:dst.value,provider:p.value,endpoint:ep.value,model:model.value,key:key.value,mmEmail:mmEmail.value,mmKey:mmKey.value};try{await fetch("/settings",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(j)})}catch(e){}}p.addEventListener("change",()=>{preset(true);showBoxes();save()});[src,dst,ep,model,key,mmEmail,mmKey].forEach(x=>x.addEventListener("change",save));[key,ep,model,mmEmail,mmKey].forEach(x=>x.addEventListener("input",()=>{clearTimeout(timer);timer=setTimeout(save,600)}));async function tr(v){if(p.value!=="mymemory")return trAI(v);let u="https://api.mymemory.translated.net/get?q="+encodeURIComponent(v)+"&langpair="+encodeURIComponent(src.value+"|"+dst.value);if(mmEmail.value)u+="&de="+encodeURIComponent(mmEmail.value);if(mmKey.value)u+="&key="+encodeURIComponent(mmKey.value);let r=await fetch(u);let j=await r.json();return j.responseData&&j.responseData.translatedText?j.responseData.translatedText:""}function chatUrl(){let u=ep.value.trim().replace(/\/+$/,"");return u.endsWith("/chat/completions")?u:u+"/chat/completions"}async function trAI(v){if(!ep.value||!model.value||!key.value)throw Error("missing ai settings");let r=await fetch(chatUrl(),{method:"POST",headers:{"Content-Type":"application/json","Authorization":"Bearer "+key.value},body:JSON.stringify({model:model.value,messages:[{role:"system",content:"Translate the user text to "+dst.value+". Return only the translation."},{role:"user",content:v}]})});let j=await r.json();return j.choices&&j.choices[0]&&j.choices[0].message?j.choices[0].message.content:""}async function sendText(){const v=t.value.trim();if(!v){m.textContent="请输入内容后再发送。";m.className="m e";return}b.disabled=true;m.textContent="翻译中...";m.className="m";try{await save();const tv=await tr(v);const out=tv?v+"\n"+tv:v;const r=await fetch("/send",{method:"POST",headers:{"Content-Type":"text/plain;charset=utf-8"},body:out});if(!r.ok)throw Error();t.value="";m.textContent="已翻译并发送到 VRChat。";s.textContent="刚刚发送成功"}catch(e){m.textContent=e.message==="missing ai settings"?"请先填写 AI endpoint、model 和 API Key。":"翻译失败或发送失败。若使用 MyMemory，请尝试填写 email，或点击按钮自行获取 key 后使用。";m.className="m e";s.textContent="连接异常"}finally{b.disabled=false;t.focus()}}t.addEventListener("keydown",e=>{if(e.key==="Enter"&&!e.ctrlKey){e.preventDefault();sendText()}});b.addEventListener("click",sendText);showBoxes();load();</script></body></html>'
html_len = $ - html

server_socket dd 0
client_socket dd 0
osc_socket dd 0
recv_len dd 0
session_count dd 0
shutdown_pending dd 0
ever_had_session dd 0
now_tick dd 0
current_id rb 32
sessions rb session_slots * 32
last_seen rd session_slots
content_len dd 0
body_have dd 0
body_ptr dd 0
settings_handle dd 0
bytes_done dd 0
recv_timeout dd 2000
settings_write_len dd 0
tmp_socket dd 0
sockaddr_len dd 16
accept_timeout dd 1000
readfds dd 0,0
select_timeout dd 1,0
hlist_ptr dd 0
best_ip_score dd 0
hostname rb 256
best_ip rb 16

server_addr dw AF_INET
            dw 0
            dd 0
            rb 8

osc_addr    dw AF_INET
            dw 0
            dd 0
            rb 8

tmp_addr    dw AF_INET
            dw 0
            dd 0
            rb 8

local_addr  dw AF_INET
            dw 0
            dd 0
            rb 8

wsa_data rb 400
recv_buf_size = 65536
recv_buf rb recv_buf_size
settings_buf_size = 4096
settings_buf rb settings_buf_size
osc_packet rb 8192

section '.idata' import data readable writeable

library kernel32,'KERNEL32.DLL',\
        shell32,'SHELL32.DLL',\
        wsock32,'WSOCK32.DLL'

include '..\tools\fasm\include\api\kernel32.inc'
include '..\tools\fasm\include\api\shell32.inc'
include '..\tools\fasm\include\api\wsock32.inc'
