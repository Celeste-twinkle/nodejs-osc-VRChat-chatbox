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
RT_ICON = 3
RT_GROUP_ICON = 14
RT_VERSION = 16
RT_MANIFEST = 24
LANG_NEUTRAL = 0

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
        invoke  GetCommandLine
        mov     esi,eax
        call    command_line_has_lan
        cmp     eax,1
        jne     bind_localhost
        mov     dword [lan_enabled],1
        mov     dword [server_addr+4],0
        jmp     bind_ready

bind_localhost:
        invoke  inet_addr,localhost
        mov     dword [server_addr+4],eax

bind_ready:
        invoke  setsockopt,[server_socket],0FFFFh,4,reuse_opt,4
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

        call    is_post_lan_enable
        cmp     eax,1
        je      handle_lan_enable

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
        call    parse_resident_flag
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client

parse_resident_flag:
        mov     esi,[body_ptr]
        mov     ecx,[settings_write_len]
        sub     ecx,14
        jle     .done
.scan:
        cmp     dword [esi],'"res'
        jne     .next
        cmp     dword [esi+4],'iden'
        jne     .next
        cmp     dword [esi+8],'t":t'
        jne     .next
        cmp     word [esi+12],'ru'
        jne     .next
        mov     dword [resident_mode],1
        ret
.next:
        inc     esi
        dec     ecx
        jnz     .scan
        mov     dword [resident_mode],0
.done:
        ret

handle_session_open:
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client

handle_session_close:
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client

handle_lan_enable:
        call    enable_lan_listener
        call    serve_lan_ip
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

is_post_lan_enable:
        mov     esi,recv_buf
        mov     edi,post_lan_enable
        mov     ecx,post_lan_enable_len
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

command_line_has_lan:
.scan:
        mov     al,[esi]
        test    al,al
        jz      .no
        cmp     al,'-'
        je      .check_dash
        cmp     al,'/'
        je      .check_slash
        inc     esi
        jmp     .scan
.check_dash:
        cmp     byte [esi+1],'-'
        jne     .next
        cmp     byte [esi+2],'l'
        jne     .next
        cmp     byte [esi+3],'a'
        jne     .next
        cmp     byte [esi+4],'n'
        jne     .next
        jmp     .yes
.check_slash:
        cmp     byte [esi+1],'l'
        jne     .next
        cmp     byte [esi+2],'a'
        jne     .next
        cmp     byte [esi+3],'n'
        jne     .next
        jmp     .yes
.next:
        inc     esi
        jmp     .scan
.yes:
        mov     eax,1
        ret
.no:
        xor     eax,eax
        ret

enable_lan_listener:
        cmp     dword [lan_enabled],1
        je      .done
        invoke  closesocket,[server_socket]
        invoke  socket,AF_INET,SOCK_STREAM,IPPROTO_TCP
        mov     [server_socket],eax
        cmp     eax,INVALID_SOCKET
        je      .fallback
        invoke  setsockopt,[server_socket],0FFFFh,4,reuse_opt,4
        invoke  htons,19001
        mov     word [server_addr+2],ax
        mov     dword [server_addr+4],0
        invoke  bind,[server_socket],server_addr,16
        cmp     eax,0
        jne     .fallback
        invoke  setsockopt,[server_socket],0FFFFh,1006h,accept_timeout,4
        invoke  listen,[server_socket],8
        mov     dword [lan_enabled],1
        ret
.fallback:
        call    restore_localhost_listener
.done:
        ret

restore_localhost_listener:
        mov     dword [lan_enabled],0
        invoke  closesocket,[server_socket]
        invoke  socket,AF_INET,SOCK_STREAM,IPPROTO_TCP
        mov     [server_socket],eax
        cmp     eax,INVALID_SOCKET
        je      .done
        invoke  setsockopt,[server_socket],0FFFFh,4,reuse_opt,4
        invoke  htons,19001
        mov     word [server_addr+2],ax
        invoke  inet_addr,localhost
        mov     dword [server_addr+4],eax
        invoke  bind,[server_socket],server_addr,16
        cmp     eax,0
        jne     .done
        invoke  setsockopt,[server_socket],0FFFFh,1006h,accept_timeout,4
        invoke  listen,[server_socket],8
.done:
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
        cmp     eax,[idle_timeout]
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
        cmp     dword [resident_mode],1
        je      .ret
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
        cmp     dword [lan_enabled],1
        jne     .fallback
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
post_lan_enable db 'POST /lan-enable '
post_lan_enable_len = $ - post_lan_enable
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
reuse_opt dd 1
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
     db '.row{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-bottom:12px}.row2{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px}.row3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-bottom:12px}select,input{width:100%;border:1px solid #d8dee8;border-radius:8px;padding:10px;background:#fbfcfe;color:#111827}label{display:block;color:#667085;font-size:12px;margin:0 0 5px}.lan{display:flex;justify-content:space-between;gap:12px;align-items:center;padding:10px 12px;border:1px solid #d8dee8;border-radius:8px;margin-bottom:12px;background:#fbfcfe}.toggle{display:flex;align-items:center;gap:8px;margin-bottom:12px;color:#111827;font-size:13px}.toggle input{width:auto}.lan b{font-size:13px}.lan-note{display:block;margin-top:3px;color:#667085;font-size:12px}.lan code{font-size:13px;color:#115e59}.lan-actions{display:flex;gap:8px;align-items:center}.lan button{min-width:0;padding:9px 12px;font-size:13px}.a{display:flex;align-items:center;justify-content:space-between;gap:14px;margin-top:14px}.h,.m,.warn{color:#667085;font-size:13px}.warn{padding:10px;border:1px solid #fecdca;background:#fff5f4;color:#b42318;border-radius:8px;margin:0 0 12px}.hide{display:none}.linkbtn{display:flex;align-items:center;justify-content:center;border-radius:8px;padding:10px 12px;background:#eef8f6;color:#115e59;text-decoration:none;font-size:13px;font-weight:650}button{min-width:132px;border:0;border-radius:8px;padding:12px 18px;background:#0f766e;color:white;font:inherit;font-weight:650;cursor:pointer}button:hover{background:#115e59}button:active{transform:translateY(1px)}button:disabled{cursor:wait;opacity:.72}.e{color:#b42318}@media(max-width:560px){body{padding:12px}header,.a,.row,.row2,.row3,.lan{align-items:stretch;grid-template-columns:1fr;flex-direction:column}.lan-actions{align-items:stretch;flex-direction:column}button{width:100%}}.hlist{max-height:240px;overflow-y:auto;margin-top:12px;border:1px solid #d8dee8;border-radius:8px}.hitem{display:flex;justify-content:space-between;align-items:center;padding:10px 14px;border-bottom:1px solid #e5e7eb;cursor:pointer;user-select:none;-webkit-user-select:none;transition:background .15s}.hitem:last-child{border-bottom:0}.hitem:hover{background:#f0fdf4}.hitem:active{background:#d1fae5}.htime{color:#9ca3af;font-size:11px;white-space:nowrap;margin-left:12px}.htext{flex:1;overflow:hidden}.hsrc{font-size:14px;color:#374151;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.htrans{font-size:12px;color:#9ca3af;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;margin-top:2px}.hitem .del{color:#d1d5db;font-size:16px;line-height:1;padding:2px 6px;border-radius:4px}.hitem .del:hover{color:#ef4444;background:#fef2f2}.hitem.pressing{position:relative;overflow:hidden;background:#ecfdf5}.hitem.pressing::after{content:"";position:absolute;left:0;bottom:0;height:3px;background:#10b981;animation:fillBar .6s ease-out forwards}@keyframes fillBar{from{width:0}to{width:100%}}.fmt{margin-bottom:12px}.fmt select{width:auto;min-width:140px}</style></head>'
     db '<body><main><header><h1>VRC Chatbox OSC</h1><div class="s" id="status">本地服务已连接</div></header><section class="c"><div class="lan"><div><b>局域网访问地址</b><span class="lan-note">可在同一路由其他设备访问，如连接路由器wifi的手机</span></div><div class="lan-actions"><code id="lan">仅本机</code><button id="lanBtn" type="button">允许局域网连接</button></div></div><label class="toggle"><input id="resident" type="checkbox">常驻模式（不自动退出）</label><label class="toggle"><input id="trOn" type="checkbox">启用翻译</label><div id="trBox" class="hide"><div class="row3"><div><label>源语言</label><select id="src"><option value="zh-CN">简体中文</option><option value="en">English</option><option value="ja">日本語</option><option value="ko">한국어</option><option value="fr">Français</option><option value="de">Deutsch</option><option value="es">Español</option></select></div><div><label>目标语言</label><select id="dst"><option value="en">English</option><option value="zh-CN">简体中文</option><option value="ja">日本語</option><option value="ko">한국어</option><option value="fr">Français</option><option value="de">Deutsch</option><option value="es">Español</option></select></div><div><label>翻译服务</label><select id="provider"><option value="mymemory">MyMemory 免费公开 API</option><option value="openai">ChatGPT / OpenAI</option><option value="deepseek">DeepSeek</option><option value="hunyuan">腾讯混元</option><option value="custom">自定义 OpenAI 兼容 API</option></select></div></div><div class="warn">Key 会保存到本机 settings.json。不要把这个文件复制或发送给任何人。若 MyMemory 翻译失败或提示额度不足，请尝试填写 email，或自行获取 key 后使用。</div><div id="mmBox" class="row"><input id="mmEmail" placeholder="MyMemory email，可提升免费额度"><input id="mmKey" placeholder="MyMemory key，可选"><a class="linkbtn" target="_blank" href="https://mymemory.translated.net/doc/keygen.php">获取 MyMemory key</a></div><div id="aiBox" class="row hide"><input id="endpoint" placeholder="AI Base URL，例如 https://api.openai.com/v1"><input id="model" placeholder="模型，例如 gpt-4o-mini / deepseek-chat"><input id="key" placeholder="AI API Key"></div><div id="fmtBox" class="fmt hide"><label>翻译格式</label><select id="fmt"><option value="both">原文 + 译文</option><option value="trans">仅译文</option><option value="orig">仅原文（不翻译）</option></select></div></div></div><textarea id="text" autofocus placeholder="输入要直接发送到 VRChat Chatbox 的文字。"></textarea><div id="hlist" class="hlist"></div><div class="a"><div class="h" id="hint">Enter 发送，Ctrl + Enter 换行</div><button id="button" type="button">发送</button></div><div class="m" id="message"></div></section></main>'
     db '<script>const $=id=>document.getElementById(id),b=$("button"),t=$("text"),m=$("message"),s=$("status"),lan=$("lan"),lanBtn=$("lanBtn"),trOn=$("trOn"),trBox=$("trBox"),hint=$("hint"),src=$("src"),dst=$("dst"),p=$("provider"),ep=$("endpoint"),model=$("model"),key=$("key"),mmEmail=$("mmEmail"),mmKey=$("mmKey"),mmBox=$("mmBox"),aiBox=$("aiBox"),fmt=$("fmt"),hlist=$("hlist"),fmtBox=$("fmtBox"),resident=$("resident");let timer=0,history=[],longPressTimer=0,longPressFired=false;const sid=(Date.now().toString(36)+Math.random().toString(36).slice(2,10)).slice(0,31);function beat(){fetch("/heartbeat?id="+encodeURIComponent(sid),{method:"POST"}).catch(()=>{})}beat();setInterval(beat,3000);async function refreshLan(){try{const r=await fetch("/lan-ip");const j=await r.json();const on=j.ip!=="127.0.0.1";lan.textContent=on?"http://"+j.ip+":19001":"仅本机";lanBtn.disabled=on;lanBtn.textContent=on?"已允许":"允许局域网连接"}catch(e){lan.textContent="仅本机";lanBtn.disabled=false;lanBtn.textContent="允许局域网连接"}}async function enableLan(){lanBtn.disabled=true;lanBtn.textContent="正在开启";try{const r=await fetch("/lan-enable",{method:"POST"});const j=await r.json();const on=j.ip!=="127.0.0.1";lan.textContent=on?"http://"+j.ip+":19001":"开启失败";lanBtn.disabled=on;lanBtn.textContent=on?"已允许":"重试";s.textContent=on?"已允许局域网连接":"局域网连接开启失败"}catch(e){lan.textContent="开启失败";lanBtn.disabled=false;lanBtn.textContent="重试"}}refreshLan();function showBoxes(){let on=trOn.checked,mm=p.value==="mymemory",f=fmt.value;trBox.className=on?"":"hide";mmBox.className=on&&mm?"row":"row hide";aiBox.className=on&&!mm?"row":"row hide";fmtBox.className=on?"fmt":"hide";let lb=f==="orig"?"发送":f==="trans"?"翻译发送":"翻译发送";b.textContent=on?lb:"发送";hint.textContent=on?"Enter "+lb+"，Shift + Enter 换行":"Enter 发送，Shift + Enter 换行";t.placeholder=on?(f==="orig"?"输入要发送的文字（不翻译）。":f==="trans"?"输入源语言。发送时仅发送译文。":"输入源语言。发送时会把译文换行拼接到源语言后面。"):"输入要直接发送到 VRChat Chatbox 的文字。"}function preset(force){const ps={openai:["https://api.openai.com/v1","gpt-4o-mini"],deepseek:["https://api.deepseek.com","deepseek-chat"],hunyuan:["https://api.hunyuan.cloud.tencent.com/v1","hunyuan-turbos-latest"]}[p.value];if(!ps)return;if(force||!ep.value)ep.value=ps[0];if(force||!model.value)model.value=ps[1]}async function load(){try{const r=await fetch("/settings");const j=await r.json();trOn.checked=!!j.translate;src.value=j.src||src.value;dst.value=j.dst||dst.value;p.value=j.provider||p.value;ep.value=j.endpoint||"";model.value=j.model||"";key.value=j.key||"";mmEmail.value=j.mmEmail||"";mmKey.value=j.mmKey||"";fmt.value=j.format||fmt.value;resident.checked=!!j.resident;if(j.resident)save();preset(false);showBoxes()}catch(e){showBoxes()}}async function save(){const j={translate:trOn.checked,src:src.value,dst:dst.value,provider:p.value,endpoint:ep.value,model:model.value,key:key.value,mmEmail:mmEmail.value,mmKey:mmKey.value,format:fmt.value,resident:resident.checked};try{await fetch("/settings",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(j)})}catch(e){}}trOn.addEventListener("change",()=>{showBoxes();save()});resident.addEventListener("change",save);fmt.addEventListener("change",()=>{showBoxes();save()});p.addEventListener("change",()=>{preset(true);showBoxes();save()});[src,dst,ep,model,key,mmEmail,mmKey].forEach(x=>x.addEventListener("change",save));[key,ep,model,mmEmail,mmKey].forEach(x=>x.addEventListener("input",()=>{clearTimeout(timer);timer=setTimeout(save,600)}));async function tr(v){if(p.value!=="mymemory")return trAI(v);let u="https://api.mymemory.translated.net/get?q="+encodeURIComponent(v)+"&langpair="+encodeURIComponent(src.value+"|"+dst.value);if(mmEmail.value)u+="&de="+encodeURIComponent(mmEmail.value);if(mmKey.value)u+="&key="+encodeURIComponent(mmKey.value);let r=await fetch(u);let j=await r.json();return j.responseData&&j.responseData.translatedText?j.responseData.translatedText:""}function chatUrl(){let u=ep.value.trim().replace(/\/+$/,"");return u.endsWith("/chat/completions")?u:u+"/chat/completions"}async function trAI(v){if(!ep.value||!model.value||!key.value)throw Error("missing ai settings");let r=await fetch(chatUrl(),{method:"POST",headers:{"Content-Type":"application/json","Authorization":"Bearer "+key.value},body:JSON.stringify({model:model.value,messages:[{role:"system",content:"Translate the user text to "+dst.value+". Return only the translation."},{role:"user",content:v}]})});let j=await r.json();return j.choices&&j.choices[0]&&j.choices[0].message?j.choices[0].message.content:""}async function sendText(){const v=t.value.trim();if(!v){m.textContent="请输入内容后再发送。";m.className="m e";return}b.disabled=true;m.textContent=trOn.checked?"翻译中...":"发送中...";m.className="m";try{await save();let tv="",out="";if(trOn.checked&&fmt.value!=="orig"){tv=await tr(v)}if(trOn.checked&&fmt.value==="trans"&&!tv){throw Error("empty trans")}if(trOn.checked){if(fmt.value==="trans")out=tv;else if(fmt.value==="orig")out=v;else out=v+"\n"+tv}else{out=v}const r=await fetch("/send",{method:"POST",headers:{"Content-Type":"text/plain;charset=utf-8"},body:out});if(!r.ok)throw Error();history.unshift({text:v,trans:tv,time:new Date().toLocaleTimeString()});renderHistory();t.value="";m.textContent=trOn.checked?"已翻译并发送到 VRChat。":"已发送到 VRChat。";s.textContent="刚刚发送成功"}catch(e){m.textContent=e.message==="missing ai settings"?"请先填写 AI endpoint、model 和 API Key。":e.message==="empty trans"?"仅译文模式：翻译结果为空，请重试或切换格式。":trOn.checked?"翻译失败或发送失败。若使用 MyMemory，请尝试填写 email，或点击按钮自行获取 key 后使用。":"发送失败，请确认 VRChat OSC 已开启。";m.className="m e";s.textContent="连接异常"}finally{b.disabled=false;t.focus()}}t.addEventListener("keydown",e=>{if(e.key==="Enter"&&!e.shiftKey){e.preventDefault();sendText()}});b.addEventListener("click",sendText);lanBtn.addEventListener("click",enableLan);function renderHistory(){hlist.innerHTML=history.map((h,i)=>"<div class=\"hitem\" id=\"hitem-"+i+"\" onmousedown=\"startLongPress(event,"+i+")\" onmouseup=\"endLongPress(event,"+i+")\" onmouseleave=\"cancelLongPress()\" ontouchstart=\"startLongPress(event,"+i+")\" ontouchend=\"endLongPress(event,"+i+")\" ontouchmove=\"cancelLongPress()\"><span class=\"htext\"><span class=\"hsrc\">"+h.text.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/\"/g,"&quot;")+"</span><span class=\"htrans\">"+(h.trans||"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/\"/g,"&quot;")+"</span></span><span class=\"htime\">"+h.time+"</span><span class=\"del\" onmousedown=\"event.stopPropagation()\" onmouseup=\"event.stopPropagation()\" onclick=\"event.stopPropagation();delHistory("+i+")\">&times;</span></div>").join("")}function startLongPress(e,i){clearTimeout(longPressTimer);longPressFired=false;var el=$("hitem-"+i);if(el)el.classList.add("pressing");longPressTimer=setTimeout(function(){longPressFired=true;if(el)el.classList.remove("pressing");resendFromHistory(i)},600)}function endLongPress(e,i){clearTimeout(longPressTimer);var el=$("hitem-"+i);if(el)el.classList.remove("pressing");if(!longPressFired){t.value=history[i].text;t.focus();m.textContent="已填入历史消息，修改后按 Enter 发送";m.className="m"}}function cancelLongPress(){clearTimeout(longPressTimer);var els=document.querySelectorAll(".hitem.pressing");for(var j=0;j<els.length;j++)els[j].classList.remove("pressing")}async function resendFromHistory(i){let h=history[i];let ht=h.trans||"";b.disabled=true;m.textContent="重发中...";m.className="m";try{let out="";if(trOn.checked){if(fmt.value==="trans"){if(!ht)throw Error("empty trans");out=ht}else if(fmt.value==="orig")out=h.text;else out=h.text+"\n"+ht}else{out=h.text}const r=await fetch("/send",{method:"POST",headers:{"Content-Type":"text/plain;charset=utf-8"},body:out});if(!r.ok)throw Error();m.textContent="已重发到 VRChat。";s.textContent="刚刚重发成功"}catch(e){m.textContent=e.message==="empty trans"?"仅译文模式：翻译结果为空，请重试或切换格式。":"重发失败，请确认 VRChat OSC 已开启。";m.className="m e";s.textContent="连接异常"}finally{b.disabled=false}}function delHistory(i){history.splice(i,1);renderHistory()}showBoxes();load();</script></body></html>'
html_len = $ - html

server_socket dd 0
client_socket dd 0
osc_socket dd 0
recv_len dd 0
session_count dd 0
shutdown_pending dd 0
ever_had_session dd 0
lan_enabled dd 0
resident_mode dd 0
idle_timeout dd 30000
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

section '.rsrc' resource data readable

directory RT_ICON,icons,\
          RT_GROUP_ICON,group_icons,\
          RT_VERSION,versions,\
          RT_MANIFEST,manifests

resource icons,\
         1,LANG_NEUTRAL,app_icon_16,\
         2,LANG_NEUTRAL,app_icon_32,\
         3,LANG_NEUTRAL,app_icon_48

resource group_icons,\
         1,LANG_NEUTRAL,app_icon_group

resource versions,\
         1,LANG_NEUTRAL,version_info

resource manifests,\
         1,LANG_NEUTRAL,app_manifest

icon app_icon_group,\
     app_icon_16,'assets\icon-gpt-16.ico',\
     app_icon_32,'assets\icon-gpt-q8-32.ico',\
     app_icon_48,'assets\icon-gpt-q8-48.ico'

versioninfo version_info,VOS_NT_WINDOWS32,VFT_APP,VFT2_UNKNOWN,0409h,04E4h,\
            'CompanyName','osc-VRChat-chatbox',\
            'FileDescription','VRChat Chatbox OSC local helper',\
            'FileVersion','1.0.0.0',\
            'InternalName','vrc-chatbox-osc.exe',\
            'OriginalFilename','vrc-chatbox-osc.exe',\
            'ProductName','VRC Chatbox OSC',\
            'ProductVersion','1.0.0.0'

resdata app_manifest
  db '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',13,10
  db '<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">',13,10
  db '  <assemblyIdentity version="1.0.0.0" processorArchitecture="x86" name="VRCChatboxOSC" type="win32"/>',13,10
  db '  <description>VRChat Chatbox OSC local helper</description>',13,10
  db '  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">',13,10
  db '    <security>',13,10
  db '      <requestedPrivileges>',13,10
  db '        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>',13,10
  db '      </requestedPrivileges>',13,10
  db '    </security>',13,10
  db '  </trustInfo>',13,10
  db '</assembly>'
endres
