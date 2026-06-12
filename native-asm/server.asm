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
WM_COMMAND = 0111h
WM_USER = 0400h
WM_TRAY = WM_USER + 1
WM_RBUTTONUP = 0205h
WM_LBUTTONDBLCLK = 0203h
ID_TRAY_OPEN = 1001
ID_TRAY_EXIT = 1002
RT_ICON = 3
RT_GROUP_ICON = 14
RT_VERSION = 16
RT_MANIFEST = 24
LANG_NEUTRAL = 0

section '.text' code readable executable

start:
        call    set_cwd_to_exe_dir
        call    load_settings_flags

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
        je      bind_lan
        cmp     dword [lan_allowed],1
        jne     bind_localhost
bind_lan:
        mov     dword [lan_enabled],1
        mov     dword [server_addr+4],0
        jmp     bind_ready

bind_localhost:
        invoke  inet_addr,localhost
        mov     dword [server_addr+4],eax

bind_ready:
        invoke  bind,[server_socket],server_addr,16
        cmp     eax,0
        jne     open_existing_and_exit
        invoke  setsockopt,[server_socket],0FFFFh,1006h,accept_timeout,4
        invoke  listen,[server_socket],8

        call    setup_tray
        invoke  GetCommandLine
        mov     esi,eax
        call    command_line_has_minimized
        cmp     eax,1
        je      accept_loop
        invoke  ShellExecute,0,open_action,url,0,0,1

accept_loop:
        call    process_messages
        cmp     dword [quit_requested],1
        je      shutdown_now
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

        call    is_post_typing
        cmp     eax,1
        je      handle_typing

        call    serve_index
        jmp     close_client

handle_typing:
        call    find_body
        test    eax,eax
        jz      send_no_content
        mov     esi,eax
        cmp     byte [esi],'t'
        jne     .off
        push    1
        call    send_typing_osc
        jmp     send_no_content
.off:
        push    0
        call    send_typing_osc
        jmp     send_no_content

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
        mov     edx,recv_buf_size-1
        sub     edx,[recv_len]
        jle     .settings_len_ready
        invoke  recv,[client_socket],eax,edx,0
        cmp     eax,0
        jle     .settings_len_ready
        add     [recv_len],eax
        add     [body_have],eax
        jmp     .read_more_settings

.settings_len_ready:
        mov     ecx,[content_len]
        cmp     ecx,[body_have]
        jle     .settings_have_ok
        mov     ecx,[body_have]
.settings_have_ok:
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
        call    settings_json_valid
        cmp     eax,1
        je      .settings_valid
        call    use_default_settings_flags
        call    update_startup_setting
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client
.settings_valid:
        call    parse_settings_flags
        call    update_startup_setting
        invoke  send,[client_socket],http_204,http_204_len,0
        jmp     close_client

load_settings_flags:
        invoke  CreateFile,settings_file,80000000h,1,0,3,80h,0
        cmp     eax,-1
        je      .default
        mov     [settings_handle],eax
        invoke  ReadFile,[settings_handle],settings_buf,settings_buf_size,bytes_done,0
        invoke  CloseHandle,[settings_handle]
        mov     eax,[bytes_done]
        mov     [settings_write_len],eax
        mov     dword [body_ptr],settings_buf
        call    settings_json_valid
        cmp     eax,1
        jne     .default
        call    parse_settings_flags
.done:
        ret
.default:
        call    use_default_settings_flags
        ret

use_default_settings_flags:
        call    write_default_settings
        mov     dword [body_ptr],default_settings
        mov     dword [settings_write_len],default_settings_len
        call    parse_settings_flags
        ret

write_default_settings:
        invoke  CreateFile,settings_file,40000000h,0,0,2,80h,0
        cmp     eax,-1
        je      .done
        mov     [settings_handle],eax
        invoke  WriteFile,[settings_handle],default_settings,default_settings_len,bytes_done,0
        invoke  CloseHandle,[settings_handle]
.done:
        ret

settings_json_valid:
        mov     ecx,[settings_write_len]
        test    ecx,ecx
        jz      .no
        mov     esi,[body_ptr]
.scan_start:
        mov     al,[esi]
        cmp     al,' '
        je      .next_start
        cmp     al,9
        je      .next_start
        cmp     al,13
        je      .next_start
        cmp     al,10
        je      .next_start
        cmp     al,'{'
        jne     .no
        jmp     .scan_end_init
.next_start:
        inc     esi
        dec     ecx
        jnz     .scan_start
        jmp     .no
.scan_end_init:
        mov     ecx,[settings_write_len]
        mov     esi,[body_ptr]
        add     esi,ecx
        dec     esi
.scan_end:
        mov     al,[esi]
        cmp     al,' '
        je      .prev_end
        cmp     al,9
        je      .prev_end
        cmp     al,13
        je      .prev_end
        cmp     al,10
        je      .prev_end
        cmp     al,'}'
        jne     .no
        mov     edi,json_translate_key
        mov     edx,json_translate_key_len
        call    json_has_true
        cmp     eax,1
        jne     .no
        mov     edi,json_provider_key
        mov     edx,json_provider_key_len
        call    json_has_true
        cmp     eax,1
        jne     .no
        mov     eax,1
        ret
.prev_end:
        dec     esi
        dec     ecx
        jnz     .scan_end
.no:
        xor     eax,eax
        ret

parse_settings_flags:
        mov     edi,json_resident_true
        mov     edx,json_resident_true_len
        call    json_has_true
        mov     [resident_mode],eax
        mov     edi,json_startup_true
        mov     edx,json_startup_true_len
        call    json_has_true
        mov     [startup_mode],eax
        mov     edi,json_start_minimized_true
        mov     edx,json_start_minimized_true_len
        call    json_has_true
        mov     [startup_minimized],eax
        mov     edi,json_lan_true
        mov     edx,json_lan_true_len
        call    json_has_true
        mov     [lan_allowed],eax
        cmp     dword [resident_mode],1
        je      .done
        mov     dword [startup_mode],0
        mov     dword [startup_minimized],0
.done:
        ret

set_cwd_to_exe_dir:
        invoke  GetModuleFileName,0,exe_path,260
        mov     esi,exe_path
        xor     edi,edi
.scan:
        mov     al,[esi]
        test    al,al
        jz      .found_end
        cmp     al,'\'
        jne     .next
        mov     edi,esi
.next:
        inc     esi
        jmp     .scan
.found_end:
        test    edi,edi
        jz      .done
        mov     byte [edi],0
        invoke  SetCurrentDirectory,exe_path
.done:
        ret

json_has_true:
        mov     esi,[body_ptr]
        mov     ecx,[settings_write_len]
        sub     ecx,edx
        jl      .no
        inc     ecx
.scan:
        push    esi
        push    edi
        push    ecx
        mov     ecx,edx
        repe    cmpsb
        sete    al
        pop     ecx
        pop     edi
        pop     esi
        cmp     al,1
        je      .yes
        inc     esi
        loop    .scan
.no:
        xor     eax,eax
        ret
.yes:
        mov     eax,1
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
        invoke  GetCommandLine
        mov     esi,eax
        call    command_line_has_minimized
        cmp     eax,1
        je      .skip_open
        invoke  ShellExecute,0,open_action,url,0,0,1
.skip_open:
        invoke  closesocket,[server_socket]
        invoke  closesocket,[osc_socket]
        invoke  WSACleanup
        invoke  ExitProcess,0

shutdown_now:
        call    remove_tray
        invoke  closesocket,[server_socket]
        invoke  closesocket,[osc_socket]
        invoke  WSACleanup
        invoke  ExitProcess,0

setup_tray:
        invoke  GetModuleHandle,0
        mov     [app_instance],eax
        mov     [tray_wc.hInstance],eax
        mov     [tray_wc.lpfnWndProc],tray_wnd_proc
        mov     [tray_wc.lpszClassName],tray_class
        invoke  RegisterClass,tray_wc
        invoke  CreateWindowEx,0,tray_class,tray_title,0,0,0,0,0,0,0,[app_instance],0
        mov     [tray_hwnd],eax
        test    eax,eax
        jz      .done
        invoke  GetSystemMetrics,SM_CXSMICON
        mov     ebx,eax
        invoke  GetSystemMetrics,SM_CYSMICON
        invoke  LoadImage,[app_instance],1,IMAGE_ICON,ebx,eax,LR_DEFAULTCOLOR
        test    eax,eax
        jnz     .icon_ready
        invoke  LoadIcon,[app_instance],1
        test    eax,eax
        jnz     .icon_ready
        invoke  LoadIcon,0,IDI_APPLICATION
.icon_ready:
        mov     [tray_icon],eax
        mov     [tray_nid.cbSize],sizeof.NOTIFYICONDATAA
        mov     eax,[tray_hwnd]
        mov     [tray_nid.hWnd],eax
        mov     [tray_nid.uID],1
        mov     [tray_nid.uFlags],NIF_MESSAGE+NIF_ICON+NIF_TIP
        mov     [tray_nid.uCallbackMessage],WM_TRAY
        mov     eax,[tray_icon]
        mov     [tray_nid.hIcon],eax
        mov     esi,tray_tip
        mov     edi,tray_nid.szTip
        mov     ecx,tray_tip_len
        rep     movsb
        invoke  Shell_NotifyIcon,NIM_ADD,tray_nid
.done:
        ret

remove_tray:
        cmp     dword [tray_hwnd],0
        je      .done
        invoke  Shell_NotifyIcon,NIM_DELETE,tray_nid
        invoke  DestroyWindow,[tray_hwnd]
        mov     dword [tray_hwnd],0
.done:
        ret

process_messages:
.loop:
        invoke  PeekMessage,msg,0,0,0,PM_REMOVE
        test    eax,eax
        jz      .done
        cmp     dword [msg+4],0012h
        jne     .dispatch
        mov     dword [quit_requested],1
        jmp     .loop
.dispatch:
        invoke  TranslateMessage,msg
        invoke  DispatchMessage,msg
        jmp     .loop
.done:
        ret

show_tray_menu:
        push    ebx
        call    select_tray_menu_texts
        invoke  CreatePopupMenu
        mov     [tray_menu],eax
        test    eax,eax
        jz      .done
        invoke  AppendMenuW,[tray_menu],0,ID_TRAY_OPEN,[tray_open_text]
        invoke  AppendMenuW,[tray_menu],0,ID_TRAY_EXIT,[tray_exit_text]
        invoke  GetCursorPos,pt
        invoke  SetForegroundWindow,[tray_hwnd]
        invoke  TrackPopupMenu,[tray_menu],TPM_RIGHTBUTTON+TPM_RETURNCMD,[pt.x],[pt.y],0,[tray_hwnd],0
        mov     ebx,eax
        invoke  DestroyMenu,[tray_menu]
        cmp     ebx,ID_TRAY_OPEN
        je      .open
        cmp     ebx,ID_TRAY_EXIT
        je      .exit
        jmp     .done
.open:
        invoke  ShellExecute,0,open_action,url,0,0,1
        jmp     .done
.exit:
        mov     dword [quit_requested],1
.done:
        pop     ebx
        ret

select_tray_menu_texts:
        mov     dword [tray_open_text],tray_menu_open_en_w
        mov     dword [tray_exit_text],tray_menu_exit_en_w
        invoke  GetUserDefaultLangID
        and     eax,03ffh
        cmp     eax,LANG_CHINESE
        je      .zh
        cmp     eax,LANG_JAPANESE
        je      .ja
        cmp     eax,LANG_KOREAN
        je      .ko
        ret
.zh:
        mov     dword [tray_open_text],tray_menu_open_zh_w
        mov     dword [tray_exit_text],tray_menu_exit_zh_w
        ret
.ja:
        mov     dword [tray_open_text],tray_menu_open_ja_w
        mov     dword [tray_exit_text],tray_menu_exit_ja_w
        ret
.ko:
        mov     dword [tray_open_text],tray_menu_open_ko_w
        mov     dword [tray_exit_text],tray_menu_exit_ko_w
        ret

tray_wnd_proc:
        push    ebp
        mov     ebp,esp
        mov     eax,[ebp+12]
        cmp     eax,WM_TRAY
        je      .tray
        cmp     eax,0002h
        je      .destroy
        invoke  DefWindowProc,dword [ebp+8],dword [ebp+12],dword [ebp+16],dword [ebp+20]
        jmp     .ret
.tray:
        mov     eax,[ebp+20]
        cmp     eax,WM_RBUTTONUP
        je      .menu
        cmp     eax,WM_LBUTTONDBLCLK
        je      .open
        xor     eax,eax
        jmp     .ret
.menu:
        call    show_tray_menu
        xor     eax,eax
        jmp     .ret
.open:
        invoke  ShellExecute,0,open_action,url,0,0,1
        xor     eax,eax
        jmp     .ret
.destroy:
        invoke  PostQuitMessage,0
        xor     eax,eax
.ret:
        mov     esp,ebp
        pop     ebp
        ret     16

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

is_post_typing:
        mov     esi,recv_buf
        mov     edi,post_typing
        mov     ecx,post_typing_len
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

command_line_has_minimized:
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
        cmp     byte [esi+2],'m'
        jne     .next
        cmp     byte [esi+3],'i'
        jne     .next
        cmp     byte [esi+4],'n'
        jne     .next
        cmp     byte [esi+5],'i'
        jne     .next
        cmp     byte [esi+6],'m'
        jne     .next
        cmp     byte [esi+7],'i'
        jne     .next
        cmp     byte [esi+8],'z'
        jne     .next
        cmp     byte [esi+9],'e'
        jne     .next
        cmp     byte [esi+10],'d'
        jne     .next
        jmp     .yes
.check_slash:
        cmp     byte [esi+1],'m'
        jne     .next
        cmp     byte [esi+2],'i'
        jne     .next
        cmp     byte [esi+3],'n'
        jne     .next
        cmp     byte [esi+4],'i'
        jne     .next
        cmp     byte [esi+5],'m'
        jne     .next
        cmp     byte [esi+6],'i'
        jne     .next
        cmp     byte [esi+7],'z'
        jne     .next
        cmp     byte [esi+8],'e'
        jne     .next
        cmp     byte [esi+9],'d'
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

update_startup_setting:
        cmp     dword [startup_mode],1
        jne     .delete
        invoke  RegCreateKeyEx,HKEY_CURRENT_USER,startup_key,0,0,REG_OPTION_NON_VOLATILE,KEY_SET_VALUE,0,startup_key_handle,0
        cmp     eax,0
        jne     .done
        call    build_startup_command
        invoke  RegSetValueEx,[startup_key_handle],startup_value,0,REG_SZ,startup_cmd,[startup_cmd_len]
        invoke  RegCloseKey,[startup_key_handle]
        jmp     .done
.delete:
        invoke  RegOpenKeyEx,HKEY_CURRENT_USER,startup_key,0,KEY_SET_VALUE,startup_key_handle
        cmp     eax,0
        jne     .done
        invoke  RegDeleteValue,[startup_key_handle],startup_value
        invoke  RegCloseKey,[startup_key_handle]
.done:
        ret

build_startup_command:
        invoke  GetModuleFileName,0,exe_path,260
        mov     esi,exe_path
        mov     edi,startup_cmd
        mov     al,'"'
        stosb
.copy_path:
        lodsb
        test    al,al
        jz      .path_done
        stosb
        jmp     .copy_path
.path_done:
        mov     al,'"'
        stosb
        mov     esi,startup_arg
.copy_arg:
        lodsb
        stosb
        test    al,al
        jnz     .copy_arg
        dec     edi
        cmp     dword [startup_minimized],1
        jne     .no_min_arg
        mov     esi,startup_minimized_arg
.copy_min_arg:
        lodsb
        stosb
        test    al,al
        jnz     .copy_min_arg
        jmp     .finish
.no_min_arg:
        mov     byte [edi],0
        inc     edi
.finish:
        mov     eax,edi
        sub     eax,startup_cmd
        mov     [startup_cmd_len],eax
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
        mov     eax,[bytes_done]
        mov     [settings_write_len],eax
        mov     dword [body_ptr],settings_buf
        call    settings_json_valid
        cmp     eax,1
        jne     .empty
        invoke  send,[client_socket],http_200_json,http_200_json_len,0
        invoke  send,[client_socket],settings_buf,[bytes_done],0
        ret

.empty:
        call    write_default_settings
        invoke  send,[client_socket],http_200_json,http_200_json_len,0
        invoke  send,[client_socket],default_settings,default_settings_len,0
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

send_typing_osc:
        push    ebp
        mov     ebp,esp
        mov     edi,osc_packet
        mov     esi,osc_typing_addr
        mov     ecx,osc_typing_addr_len
        call    write_osc_string
        mov     eax,[ebp+8]
        test    eax,eax
        jz      .do_false
        mov     esi,osc_typing_true
        mov     ecx,osc_typing_true_len
        jmp     .do_write
.do_false:
        mov     esi,osc_typing_false
        mov     ecx,osc_typing_false_len
.do_write:
        call    write_osc_string
        mov     eax,edi
        sub     eax,osc_packet
        invoke  sendto,[osc_socket],osc_packet,eax,0,osc_addr,16
        pop     ebp
        ret     4

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
post_typing db 'POST /typing '
post_typing_len = $ - post_typing
content_length_header db 'CONTENT-LENGTH:'
settings_file db 'settings.json',0
dns_probe_ip db '8.8.8.8',0
startup_key db 'Software\Microsoft\Windows\CurrentVersion\Run',0
startup_value db 'VRC Chatbox OSC',0
startup_arg db ' --startup',0
startup_minimized_arg db ' --minimized',0
json_resident_true db '"resident":true'
json_resident_true_len = $ - json_resident_true
json_startup_true db '"startup":true'
json_startup_true_len = $ - json_startup_true
json_start_minimized_true db '"startMinimized":true'
json_start_minimized_true_len = $ - json_start_minimized_true
json_lan_true db '"lan":true'
json_lan_true_len = $ - json_lan_true
json_translate_key db '"translate"'
json_translate_key_len = $ - json_translate_key
json_provider_key db '"provider"'
json_provider_key_len = $ - json_provider_key
tray_class db 'VRCChatboxOSCTrayWindow',0
tray_title db 'VRC Chatbox OSC',0
tray_tip db 'VRC Chatbox OSC',0
tray_tip_len = $ - tray_tip
tray_menu_open_en_w du 'Open UI',0
tray_menu_exit_en_w du 'Exit',0
tray_menu_open_zh_w dw 06253h,05f00h,0055h,0049h,0
tray_menu_exit_zh_w dw 09000h,051fah,0
tray_menu_open_ja_w dw 0055h,0049h,03092h,0958bh,0304fh,0
tray_menu_exit_ja_w dw 07d42h,04e86h,0
tray_menu_open_ko_w dw 0055h,0049h,0020h,0c5f4h,0ae30h,0
tray_menu_exit_ko_w dw 0c885h,0b8cch,0

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
default_settings db '{"translate":true,"src":"zh-CN","dst":"en","provider":"mymemory","endpoint":"","model":"","key":"","mmEmail":"","mmKey":"","format":"both","uiLang":"auto","resident":false,"startup":false,"startMinimized":false,"lan":false}'
default_settings_len = $ - default_settings
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
osc_typing_addr db '/chatbox/typing'
osc_typing_addr_len = $ - osc_typing_addr
osc_typing_true db ',T'
osc_typing_true_len = $ - osc_typing_true
osc_typing_false db ',F'
osc_typing_false_len = $ - osc_typing_false

html db '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VRC Chatbox OSC</title><style>'
     db '*{box-sizing:border-box}body{margin:0;min-height:100dvh;display:grid;place-items:center;background:#f4f6f8;color:#111827;font-family:Segoe UI,system-ui,sans-serif;padding:24px}'
     db 'main{width:min(760px,100%);background:white;border:1px solid #d8dee8;border-radius:8px;box-shadow:0 18px 60px rgb(15 23 42/.10);overflow:hidden}'
     db 'header{display:flex;justify-content:space-between;gap:16px;padding:18px 20px;border-bottom:1px solid #d8dee8}h1{font-size:18px;margin:0}.s{color:#667085;font-size:13px}.s:before{content:"";display:inline-block;width:8px;height:8px;border-radius:99px;background:#0f766e;margin-right:8px}'
     db '.c{padding:20px}textarea{width:100%;min-height:260px;resize:vertical;border:1px solid #d8dee8;border-radius:8px;padding:16px;background:#fbfcfe;color:#111827;font:inherit;font-size:18px;line-height:1.55;outline:0}textarea:focus{border-color:#0f766e;box-shadow:0 0 0 3px rgb(15 118 110/.16)}.wrap{position:relative}.cnt{position:absolute;right:10px;bottom:6px;font-size:12px;color:#9ca3af;pointer-events:none}'
     db '.row{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-bottom:12px}.row2{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px}.row3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-bottom:12px}select,input{width:100%;border:1px solid #d8dee8;border-radius:8px;padding:10px;background:#fbfcfe;color:#111827}label{display:block;color:#667085;font-size:12px;margin:0 0 5px}.lan{display:flex;justify-content:space-between;gap:12px;align-items:center;padding:10px 12px;border:1px solid #d8dee8;border-radius:8px;margin-bottom:12px;background:#fbfcfe}.toggle{display:flex;align-items:center;gap:8px;margin-bottom:12px;color:#111827;font-size:13px}.toggle input{width:auto}.toggle.sub{margin-left:24px;color:#667085}.toggle:has(input:disabled){opacity:.58}.lan b{font-size:13px}.lan-note{display:block;margin-top:3px;color:#667085;font-size:12px}.lan code{font-size:13px;color:#115e59}.lan-actions{display:flex;gap:8px;align-items:center}.lan button{min-width:0;padding:9px 12px;font-size:13px}.a{display:grid;grid-template-columns:1fr auto 1fr;align-items:center;gap:14px;margin-top:14px}.rw{display:flex;justify-content:flex-end}.h,.m,.warn{color:#667085;font-size:13px}.warn{padding:10px;border:1px solid #fecdca;background:#fff5f4;color:#b42318;border-radius:8px;margin:0 0 12px}.hide{display:none}.modal{position:fixed;inset:0;z-index:20;display:grid;place-items:center;padding:18px;background:rgb(15 23 42/.32)}.modal.hide{display:none}.panel{width:min(680px,100%);max-height:min(82dvh,720px);overflow:auto;background:white;border:1px solid #d8dee8;border-radius:8px;box-shadow:0 20px 80px rgb(15 23 42/.24);padding:18px}.qrpanel{width:min(340px,calc(100vw - 32px));text-align:center}.qrpanel canvas{width:min(260px,100%);height:auto;image-rendering:pixelated;margin:6px auto 12px;display:block}.qrurl{display:block;color:#115e59;font-size:13px;word-break:break-all;text-decoration:none}.ph{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px}.ph b{font-size:16px}.x{min-width:0;padding:8px 12px;font-size:13px;background:#e5e7eb;color:#374151}.x:hover{background:#d1d5db}.linkbtn{display:flex;align-items:center;justify-content:center;border-radius:8px;padding:10px 12px;background:#eef8f6;color:#115e59;text-decoration:none;font-size:13px;font-weight:650}button{min-width:132px;border:0;border-radius:8px;padding:12px 18px;background:#0f766e;color:white;font:inherit;font-weight:650;cursor:pointer}button:hover{background:#115e59}button:active{transform:translateY(1px)}button:disabled{cursor:wait;opacity:.72}button.r{background:#dc2626}button.r:hover{background:#b91c1c}.e{color:#b42318}@media(max-width:560px){body{padding:12px;place-items:start}main{width:100%}header,.a,.row,.row2,.row3,.lan,.rw{align-items:stretch;grid-template-columns:1fr;flex-direction:column}.lan-actions{align-items:stretch;flex-direction:column}button{width:100%}.toggle.sub{margin-left:0}.modal{place-items:end;padding:0}.panel{width:100%;max-height:88dvh;border-radius:8px 8px 0 0;padding:16px}.ph{position:sticky;top:0;background:white;z-index:1;padding-bottom:10px}}.hlist{max-height:220px;overflow-y:auto;margin-top:12px;border:1px solid #d8dee8;border-radius:8px}.hlist:empty{display:none}.hitem{display:flex;justify-content:space-between;align-items:center;padding:10px 14px;border-bottom:1px solid #e5e7eb;cursor:pointer;user-select:none;-webkit-user-select:none;touch-action:none;transition:background .15s}.hitem:last-child{border-bottom:0}.hitem:hover{background:#f0fdf4}.hitem:active{background:#d1fae5}.htime{color:#9ca3af;font-size:11px;white-space:nowrap;margin-left:12px}.htext{flex:1;overflow:hidden}.hsrc{font-size:14px;color:#374151;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.htrans{font-size:12px;color:#9ca3af;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;margin-top:2px}.hitem .del{color:#d1d5db;font-size:16px;line-height:1;padding:2px 6px;border-radius:4px}.hitem .del:hover{color:#ef4444;background:#fef2f2}.hitem.pressing{position:relative;overflow:hidden;background:#ecfdf5}.hitem.pressing::after{content:"";position:absolute;left:0;bottom:0;height:3px;background:#10b981;animation:fillBar .6s ease-out forwards}@keyframes fillBar{from{width:0}to{width:100%}}.fmt{margin-bottom:12px}.fmt select{width:auto;min-width:140px}.r{min-width:0;padding:9px 12px;font-size:13px}</style></head>'
     db '<body><main><header><h1>VRC Chatbox OSC</h1><div class="s" id="status">本地服务已连接</div></header><section class="c"><div class="lan"><div><b>局域网访问地址</b><span class="lan-note">可在同一路由其他设备访问，如连接路由器wifi的手机</span></div><div class="lan-actions"><code id="lan">仅本机</code><button id="settingsBtn" type="button">设置</button><button id="qrBtn" class="hide" type="button">二维码</button><button id="lanBtn" type="button">允许局域网连接</button></div></div><div id="qrModal" class="modal hide"><div class="panel qrpanel"><div class="ph"><b>局域网二维码</b><button id="qrClose" class="x" type="button">关闭</button></div><canvas id="qrCanvas" width="264" height="264"></canvas><a id="qrLink" class="qrurl" target="_blank" href="#"></a></div></div><div id="settingsModal" class="modal hide"><div class="panel"><div class="ph"><b>设置</b><button id="settingsClose" class="x" type="button">关闭</button></div><div class="row2"><div><label id="uiLangLabel">UI 语言</label><select id="uiLang"><option value="auto">Auto</option><option value="zh">中文</option><option value="en">English</option><option value="ja">日本語</option><option value="ko">한국어</option></select></div></div><label class="toggle"><input id="resident" type="checkbox">常驻模式（不自动退出）</label><label class="toggle sub"><input id="startup" type="checkbox">开机自启动</label><label class="toggle sub"><input id="startMinimized" type="checkbox">最小化自启动（开机启动时不打开浏览器）</label><label class="toggle"><input id="trOn" type="checkbox">启用翻译</label><div id="trBox" class="hide"><div class="row3"><div><label>源语言</label><select id="src"><option value="zh-CN">简体中文</option><option value="en">English</option><option value="ja">日本語</option><option value="ko">한국어</option><option value="fr">Français</option><option value="de">Deutsch</option><option value="es">Español</option></select></div><div><label>目标语言</label><select id="dst"><option value="en">English</option><option value="zh-CN">简体中文</option><option value="ja">日本語</option><option value="ko">한국어</option><option value="fr">Français</option><option value="de">Deutsch</option><option value="es">Español</option></select></div><div><label>翻译服务</label><select id="provider"><option value="mymemory">MyMemory 免费公开 API</option><option value="openai">ChatGPT / OpenAI</option><option value="deepseek">DeepSeek</option><option value="hunyuan">腾讯混元</option><option value="custom">自定义 OpenAI 兼容 API</option></select></div></div><div class="warn">Key 会保存到本机 settings.json。不要把这个文件复制或发送给任何人。若 MyMemory 翻译失败或提示额度不足，请尝试填写 email，或自行获取 key 后使用。</div><div id="mmBox" class="row"><input id="mmEmail" placeholder="MyMemory email，可提升免费额度"><input id="mmKey" placeholder="MyMemory key，可选"><a class="linkbtn" target="_blank" href="https://mymemory.translated.net/doc/keygen.php">获取 MyMemory key</a></div><div id="aiBox" class="row hide"><input id="endpoint" placeholder="AI Base URL，例如 https://api.openai.com/v1"><input id="model" placeholder="模型，例如 gpt-4o-mini / deepseek-chat"><input id="key" placeholder="AI API Key"></div><div id="fmtBox" class="fmt hide"><label>翻译格式</label><select id="fmt"><option value="both">原文 + 译文</option><option value="trans">仅译文</option><option value="orig">仅原文（不翻译）</option></select></div></div></div></div><div class="wrap"><textarea id="text" autofocus placeholder="输入要直接发送到 VRChat Chatbox 的文字。"></textarea><span id="cnt" class="cnt">0/144</span></div><div class="a"><div class="h" id="hint">Enter 发送，Shift + Enter 换行</div><button id="button" type="button">发送</button><div class="rw"><button id="clearBtn" class="r" type="button">清空</button></div></div><div class="m" id="message"></div><div id="hlist" class="hlist"></div></section></main>'
     db '<script>const $=id=>document.getElementById(id),b=$("button"),t=$("text"),m=$("message"),s=$("status"),lan=$("lan"),lanBtn=$("lanBtn"),qrBtn=$("qrBtn"),qrModal=$("qrModal"),qrClose=$("qrClose"),qrCanvas=$("qrCanvas"),qrLink=$("qrLink"),trOn=$("trOn"),trBox=$("trBox"),hint=$("hint"),src=$("src"),dst=$("dst"),p=$("provider"),ep=$("endpoint"),model=$("model"),key=$("key"),mmEmail=$("mmEmail"),mmKey=$("mmKey"),mmBox=$("mmBox"),aiBox=$("aiBox"),fmt=$("fmt"),hlist=$("hlist"),fmtBox=$("fmtBox"),uiLang=$("uiLang"),uiLangLabel=$("uiLangLabel"),resident=$("resident"),startup=$("startup"),startMinimized=$("startMinimized"),clearBtn=$("clearBtn"),cnt=$("cnt"),settingsBtn=$("settingsBtn"),settingsModal=$("settingsModal"),settingsClose=$("settingsClose");let timer=0,typingTimer=0,history=[],hidCounter=0,longPressTimer=0,longPressFired=false,lanAllowed=false;const maxHistory=20;const I18N={"zh":{"connected":"本地服务已连接","lanTitle":"局域网访问地址","lanNote":"可在同一路由其他设备访问，如连接路由器wifi的手机","localOnly":"仅本机","settings":"设置","qr":"二维码","allowLan":"允许局域网连接","lanQr":"局域网二维码","close":"关闭","resident":"常驻模式（不自动退出）","startup":"开机自启动","startMinimized":"最小化自启动（开机启动时不打开浏览器）","enableTranslate":"启用翻译","uiLang":"UI 语言","srcLang":"源语言","dstLang":"目标语言","provider":"翻译服务","warn":"Key 会保存到本机 settings.json。不要把这个文件复制或发送给任何人。若 MyMemory 翻译失败或提示额度不足，请尝试填写 email，或自行获取 key 后使用。","mmEmail":"MyMemory email，可提升免费额度","mmKey":"MyMemory key，可选","mmKeyLink":"获取 MyMemory key","aiEndpoint":"AI Base URL，例如 https://api.openai.com/v1","aiModel":"模型，例如 gpt-4o-mini / deepseek-chat","aiKey":"AI API Key","format":"翻译格式","fmtBoth":"原文 + 译文","fmtTrans":"仅译文","fmtOrig":"仅原文（不翻译）","send":"发送","translateSend":"翻译发送","clear":"清空","enterSend":"Enter 发送，Shift + Enter 换行","enterAction":"Enter {action}，Shift + Enter 换行","phDirect":"输入要直接发送到 VRChat Chatbox 的文字。","phOrig":"输入要发送的文字（不翻译）。","phTrans":"输入源语言。发送时仅发送译文。","phBoth":"输入源语言。发送时会把译文换行拼接到源语言后面。","lanFail":"开启失败","allowed":"已允许","retry":"重试","opening":"正在开启","lanOk":"已允许局域网连接","lanBad":"局域网连接开启失败","empty":"请输入内容后再发送。","translating":"翻译中...","sending":"发送中...","sentTrans":"已翻译并发送到 VRChat。","sent":"已发送到 VRChat。","sentStatus":"刚刚发送成功","missingAI":"请先填写 AI endpoint、model 和 API Key。","emptyTrans":"翻译失败或返回为空，请检查 API 配置或切换格式。","transFail":"翻译失败或发送失败。若使用 MyMemory，请尝试填写 email，或点击按钮自行获取 key 后使用。","sendFail":"发送失败，请确认 VRChat OSC 已开启。","badConn":"连接异常","historyFilled":"已填入历史消息，修改后按 Enter 发送","resending":"重发中...","resent":"已重发到 VRChat。","resentStatus":"刚刚重发成功","resendFail":"重发失败，请确认 VRChat OSC 已开启。"},"en":{"connected":"Local service connected","lanTitle":"LAN access URL","lanNote":"Use another device on the same router, such as a phone on Wi-Fi.","localOnly":"Local only","settings":"Settings","qr":"QR","allowLan":"Allow LAN access","lanQr":"LAN QR code","close":"Close","resident":"Resident mode (do not exit automatically)","startup":"Start with Windows","startMinimized":"Start minimized (do not open browser on startup)","enableTranslate":"Enable translation","uiLang":"UI language","srcLang":"Source language","dstLang":"Target language","provider":"Translation provider","warn":"Keys are saved locally in settings.json. Do not copy or share this file. If MyMemory fails or quota is low, add an email or use your own key.","mmEmail":"MyMemory email for higher free quota","mmKey":"MyMemory key, optional","mmKeyLink":"Get MyMemory key","aiEndpoint":"AI Base URL, e.g. https://api.openai.com/v1","aiModel":"Model, e.g. gpt-4o-mini / deepseek-chat","aiKey":"AI API Key","format":"Send format","fmtBoth":"Original + translation","fmtTrans":"Translation only","fmtOrig":"Original only (no translation)","send":"Send","translateSend":"Translate + send","clear":"Clear","enterSend":"Enter to send, Shift + Enter for newline","enterAction":"Enter to {action}, Shift + Enter for newline","phDirect":"Type text to send directly to VRChat Chatbox.","phOrig":"Type text to send without translation.","phTrans":"Type source text. Only the translation will be sent.","phBoth":"Type source text. Translation will be appended on the next line.","lanFail":"Failed to enable","allowed":"Allowed","retry":"Retry","opening":"Enabling","lanOk":"LAN access allowed","lanBad":"Failed to enable LAN access","empty":"Type something before sending.","translating":"Translating...","sending":"Sending...","sentTrans":"Translated and sent to VRChat.","sent":"Sent to VRChat.","sentStatus":"Sent just now","missingAI":"Fill in AI endpoint, model, and API key first.","emptyTrans":"Translation failed or returned empty. Check API settings or switch format.","transFail":"Translation or sending failed. If using MyMemory, try adding an email or your own key.","sendFail":"Send failed. Make sure VRChat OSC is enabled.","badConn":"Connection issue","historyFilled":"History message restored. Edit it, then press Enter to send.","resending":"Resending...","resent":"Resent to VRChat.","resentStatus":"Resent just now","resendFail":"Resend failed. Make sure VRChat OSC is enabled."},"ja":{"connected":"ローカルサービスに接続済み","lanTitle":"LANアクセスURL","lanNote":"同じルーター上の端末、たとえばWi-Fi接続のスマートフォンからアクセスできます。","localOnly":"このPCのみ","settings":"設定","qr":"QR","allowLan":"LAN接続を許可","lanQr":"LAN QRコード","close":"閉じる","resident":"常駐モード（自動終了しない）","startup":"Windows起動時に開始","startMinimized":"最小化起動（自動起動時にブラウザーを開かない）","enableTranslate":"翻訳を有効化","uiLang":"UI言語","srcLang":"元の言語","dstLang":"翻訳先言語","provider":"翻訳サービス","warn":"キーはローカルの settings.json に保存されます。このファイルをコピー、共有しないでください。MyMemoryが失敗する場合や上限に近い場合は、メールアドレスまたは自分のキーを設定してください。","mmEmail":"MyMemory email（無料枠を増やす）","mmKey":"MyMemory key（任意）","mmKeyLink":"MyMemory keyを取得","aiEndpoint":"AI Base URL 例: https://api.openai.com/v1","aiModel":"モデル 例: gpt-4o-mini / deepseek-chat","aiKey":"AI API Key","format":"送信形式","fmtBoth":"原文 + 翻訳","fmtTrans":"翻訳のみ","fmtOrig":"原文のみ（翻訳しない）","send":"送信","translateSend":"翻訳して送信","clear":"クリア","enterSend":"Enterで送信、Shift + Enterで改行","enterAction":"Enterで{action}、Shift + Enterで改行","phDirect":"VRChat Chatbox に直接送信する文字を入力します。","phOrig":"翻訳せず送信する文字を入力します。","phTrans":"元の言語で入力します。送信時は翻訳のみ送ります。","phBoth":"元の言語で入力します。翻訳を次の行に追加して送信します。","lanFail":"有効化に失敗","allowed":"許可済み","retry":"再試行","opening":"有効化中","lanOk":"LAN接続を許可しました","lanBad":"LAN接続の有効化に失敗しました","empty":"内容を入力してから送信してください。","translating":"翻訳中...","sending":"送信中...","sentTrans":"翻訳してVRChatへ送信しました。","sent":"VRChatへ送信しました。","sentStatus":"送信しました","missingAI":"AI endpoint、model、API Key を先に入力してください。","emptyTrans":"翻訳に失敗したか、空の結果です。API設定または形式を確認してください。","transFail":"翻訳または送信に失敗しました。MyMemoryを使う場合はメールまたはキーを設定してください。","sendFail":"送信に失敗しました。VRChat OSC が有効か確認してください。","badConn":"接続エラー","historyFilled":"履歴を入力欄に戻しました。編集してEnterで送信できます。","resending":"再送信中...","resent":"VRChatへ再送信しました。","resentStatus":"再送信しました","resendFail":"再送信に失敗しました。VRChat OSC が有効か確認してください。"},"ko":{"connected":"로컬 서비스 연결됨","lanTitle":"LAN 접속 주소","lanNote":"같은 라우터의 다른 기기, 예를 들어 Wi-Fi에 연결된 휴대폰에서 접속할 수 있습니다.","localOnly":"이 PC만","settings":"설정","qr":"QR","allowLan":"LAN 접속 허용","lanQr":"LAN QR 코드","close":"닫기","resident":"상주 모드(자동 종료 안 함)","startup":"Windows 시작 시 실행","startMinimized":"최소화 시작(자동 시작 시 브라우저 열지 않음)","enableTranslate":"번역 사용","uiLang":"UI 언어","srcLang":"원본 언어","dstLang":"대상 언어","provider":"번역 서비스","warn":"키는 로컬 settings.json에 저장됩니다. 이 파일을 복사하거나 공유하지 마세요. MyMemory가 실패하거나 한도가 부족하면 email 또는 개인 key를 설정하세요.","mmEmail":"MyMemory email, 무료 한도 증가","mmKey":"MyMemory key, 선택 사항","mmKeyLink":"MyMemory key 받기","aiEndpoint":"AI Base URL 예: https://api.openai.com/v1","aiModel":"모델 예: gpt-4o-mini / deepseek-chat","aiKey":"AI API Key","format":"전송 형식","fmtBoth":"원문 + 번역","fmtTrans":"번역만","fmtOrig":"원문만(번역 안 함)","send":"전송","translateSend":"번역 후 전송","clear":"지우기","enterSend":"Enter 전송, Shift + Enter 줄바꿈","enterAction":"Enter {action}, Shift + Enter 줄바꿈","phDirect":"VRChat Chatbox로 바로 보낼 문장을 입력하세요.","phOrig":"번역하지 않고 보낼 문장을 입력하세요.","phTrans":"원본 언어로 입력하세요. 전송 시 번역만 보냅니다.","phBoth":"원본 언어로 입력하세요. 번역을 다음 줄에 붙여 보냅니다.","lanFail":"활성화 실패","allowed":"허용됨","retry":"다시 시도","opening":"활성화 중","lanOk":"LAN 접속을 허용했습니다","lanBad":"LAN 접속 활성화 실패","empty":"내용을 입력한 뒤 전송하세요.","translating":"번역 중...","sending":"전송 중...","sentTrans":"번역 후 VRChat에 전송했습니다.","sent":"VRChat에 전송했습니다.","sentStatus":"방금 전송됨","missingAI":"AI endpoint, model, API Key를 먼저 입력하세요.","emptyTrans":"번역 실패 또는 빈 결과입니다. API 설정이나 형식을 확인하세요.","transFail":"번역 또는 전송에 실패했습니다. MyMemory 사용 시 email 또는 개인 key를 설정해 보세요.","sendFail":"전송 실패. VRChat OSC가 켜져 있는지 확인하세요.","badConn":"연결 오류","historyFilled":"히스토리 메시지를 입력창에 넣었습니다. 수정 후 Enter로 전송하세요.","resending":"재전송 중...","resent":"VRChat에 재전송했습니다.","resentStatus":"방금 재전송됨","resendFail":"재전송 실패. VRChat OSC가 켜져 있는지 확인하세요."}};let lang="zh";function pickLang(v){let n=(v&&v!=="auto"?v:(navigator.language||"zh")).toLowerCase();if(n.startsWith("ja"))return"ja";if(n.startsWith("ko"))return"ko";if(n.startsWith("en"))return"en";return"zh"}function L(k){return(I18N[lang]&&I18N[lang][k])||I18N.zh[k]||k}function tx(el,k){if(el)el.textContent=L(k)}function opt(el,i,k){if(el&&el.options[i])el.options[i].textContent=L(k)}function lab(input,k){if(!input)return;let n=input.nextSibling;if(n)n.nodeValue=L(k)}function applyLang(){lang=pickLang(uiLang.value);document.documentElement.lang=lang==="zh"?"zh-CN":lang;tx(s,"connected");tx(document.querySelector(".lan b"),"lanTitle");tx(document.querySelector(".lan-note"),"lanNote");tx(settingsBtn,"settings");tx(qrBtn,"qr");tx(document.querySelector("#qrModal .ph b"),"lanQr");tx(qrClose,"close");tx(document.querySelector("#settingsModal .ph b"),"settings");tx(settingsClose,"close");tx(uiLangLabel,"uiLang");lab(resident,"resident");lab(startup,"startup");lab(startMinimized,"startMinimized");lab(trOn,"enableTranslate");let labs=trBox.querySelectorAll("label");tx(labs[0],"srcLang");tx(labs[1],"dstLang");tx(labs[2],"provider");tx(document.querySelector(".warn"),"warn");mmEmail.placeholder=L("mmEmail");mmKey.placeholder=L("mmKey");tx(document.querySelector(".linkbtn"),"mmKeyLink");ep.placeholder=L("aiEndpoint");model.placeholder=L("aiModel");key.placeholder=L("aiKey");tx(fmtBox.querySelector("label"),"format");opt(fmt,0,"fmtBoth");opt(fmt,1,"fmtTrans");opt(fmt,2,"fmtOrig");tx(clearBtn,"clear");setLanState(qrBtn.dataset.ip||"127.0.0.1",qrBtn.dataset.fail==="1");showBoxes()}const sid=(Date.now().toString(36)+Math.random().toString(36).slice(2,10)).slice(0,31);function beat(){fetch("/heartbeat?id="+encodeURIComponent(sid),{method:"POST"}).catch(()=>{})}beat();setInterval(beat,3000);function setTyping(on){if(!on){try{navigator.sendBeacon&&navigator.sendBeacon("/typing","false")}catch(e){}}fetch("/typing",{method:"POST",body:on?"true":"false",keepalive:true}).catch(function(){})}function sendTyping(){setTyping(!!t.value.trim())}window.addEventListener("pagehide",function(){setTyping(false)});function openSettings(){settingsModal.className="modal"}function closeSettings(){settingsModal.className="modal hide"}settingsBtn.addEventListener("click",openSettings);settingsClose.addEventListener("click",closeSettings);settingsModal.addEventListener("click",function(e){if(e.target===settingsModal)closeSettings()});function openQr(){let u=qrBtn.dataset.url;if(!u)return;drawQr(qrCanvas,u);qrLink.href=u;qrLink.textContent=u;qrModal.className="modal"}function closeQr(){qrModal.className="modal hide"}qrBtn.addEventListener("click",openQr);qrClose.addEventListener("click",closeQr);qrModal.addEventListener("click",function(e){if(e.target===qrModal)closeQr()});document.addEventListener("keydown",function(e){if(e.key==="Escape"){closeSettings();closeQr()}});function setLanState(ip,fail){const on=!fail&&ip!=="127.0.0.1";const u=on?"http://"+ip+":19001":"";lanAllowed=on;qrBtn.dataset.ip=ip;qrBtn.dataset.fail=fail?"1":"0";lan.textContent=on?u:(fail?L("lanFail"):L("localOnly"));qrBtn.className=on?"":"hide";qrBtn.dataset.url=u;lanBtn.disabled=on;lanBtn.textContent=on?L("allowed"):(fail?L("retry"):L("allowLan"))}async function refreshLan(){try{const r=await fetch("/lan-ip");const j=await r.json();setLanState(j.ip,false)}catch(e){setLanState("127.0.0.1",false)}}async function enableLan(){lanBtn.disabled=true;lanBtn.textContent=L("opening");try{const r=await fetch("/lan-enable",{method:"POST"});const j=await r.json();const on=j.ip!=="127.0.0.1";setLanState(j.ip,!on);if(on)await save();s.textContent=on?L("lanOk"):L("lanBad")}catch(e){setLanState("127.0.0.1",true)}}function drawQr(c,txt){const N=29,D=55,E=15;let bits=[0,1,0,0];for(let i=7;i>=0;i--)bits.push(txt.length>>i&1);for(let ch of txt){let v=ch.charCodeAt(0);for(let i=7;i>=0;i--)bits.push(v>>i&1)}for(let i=0;i<4&&bits.length<D*8;i++)bits.push(0);while(bits.length%8)bits.push(0);let data=[];for(let i=0;i<bits.length;i+=8)data.push(bits.slice(i,i+8).reduce((a,b)=>a*2+b,0));for(let p=0xec;data.length<D;p=p==0xec?0x11:0xec)data.push(p);function gm(a,b){let r=0;for(;b;b>>=1){if(b&1)r^=a;a<<=1;if(a&256)a^=0x11d}return r}function gp(n){let r=1;while(n--)r=gm(r,2);return r}let g=[1];for(let i=0;i<E;i++){let ng=Array(g.length+1).fill(0),a=gp(i);for(let j=0;j<g.length;j++){ng[j]^=g[j];ng[j+1]^=gm(g[j],a)}g=ng}g=g.slice(1);let rem=Array(E).fill(0);for(let b of data){let f=b^rem.shift();rem.push(0);for(let i=0;i<E;i++)rem[i]^=gm(g[i],f)}let cw=data.concat(rem),m=Array.from({length:N},()=>Array(N).fill(-1));function set(x,y,v){if(x>=0&&y>=0&&x<N&&y<N)m[y][x]=v}function finder(x,y){for(let dy=-1;dy<8;dy++)for(let dx=-1;dx<8;dx++){let v=0;if(dx>=0&&dx<7&&dy>=0&&dy<7&&(dx==0||dx==6||dy==0||dy==6||(dx>=2&&dx<=4&&dy>=2&&dy<=4)))v=1;set(x+dx,y+dy,v)}}function align(x,y){for(let dy=-2;dy<=2;dy++)for(let dx=-2;dx<=2;dx++)set(x+dx,y+dy,Math.max(Math.abs(dx),Math.abs(dy))!=1?1:0)}finder(0,0);finder(N-7,0);finder(0,N-7);align(22,22);for(let i=8;i<N-8;i++){if(m[6][i]<0)set(i,6,i%2==0);if(m[i][6]<0)set(6,i,i%2==0)}for(let i=0;i<8;i++){set(N-1-i,8,0);set(8,N-1-i,0)}for(let i=0;i<6;i++){set(8,i,0);set(i,8,0)}set(8,7,0);set(8,8,0);set(7,8,0);for(let i=0;i<6;i++)set(5-i,8,0);set(8,21,1);let bi=0;for(let x=N-1,up=true;x>0;x-=2){if(x==6)x--;for(let yy=0;yy<N;yy++){let y=up?N-1-yy:yy;for(let dx=0;dx<2;dx++){let xx=x-dx;if(m[y][xx]<0){let bit=bi<cw.length*8?(cw[bi>>3]>>(7-(bi&7))&1):0;m[y][xx]=bit^((xx+y)%2==0);bi++}}}up=!up}let fmt=0b111011111000100;for(let i=0;i<15;i++){let v=fmt>>i&1;if(i<6)set(8,i,v);else if(i<8)set(8,i+1,v);else if(i==8)set(7,8,v);else set(14-i,8,v);if(i<8)set(N-1-i,8,v);else set(8,N-15+i,v)}let q=4,sc=Math.floor(c.width/(N+q*2)),ctx=c.getContext("2d");ctx.fillStyle="#fff";ctx.fillRect(0,0,c.width,c.height);ctx.fillStyle="#111827";for(let y=0;y<N;y++)for(let x=0;x<N;x++)if(m[y][x])ctx.fillRect((x+q)*sc,(y+q)*sc,sc,sc)}function showBoxes(){let on=trOn.checked,mm=p.value==="mymemory",f=fmt.value;trBox.className=on?"":"hide";mmBox.className=on&&mm?"row":"row hide";aiBox.className=on&&!mm?"row":"row hide";fmtBox.className=on?"fmt":"hide";let lb=f==="orig"?L("send"):L("translateSend");b.textContent=on?lb:L("send");hint.textContent=on?L("enterAction").replace("{action}",lb):L("enterSend");t.placeholder=on?(f==="orig"?L("phOrig"):f==="trans"?L("phTrans"):L("phBoth")):L("phDirect")}function preset(force){const ps={openai:["https://api.openai.com/v1","gpt-4o-mini"],deepseek:["https://api.deepseek.com","deepseek-chat"],hunyuan:["https://api.hunyuan.cloud.tencent.com/v1","hunyuan-turbos-latest"]}[p.value];if(!ps)return;if(force||!ep.value)ep.value=ps[0];if(force||!model.value)model.value=ps[1]}function syncStartup(){startup.disabled=!resident.checked;if(!resident.checked)startup.checked=false;startMinimized.disabled=!startup.checked;if(!startup.checked)startMinimized.checked=false}async function load(){try{const r=await fetch("/settings");const j=await r.json();trOn.checked=!!j.translate;src.value=j.src||src.value;dst.value=j.dst||dst.value;p.value=j.provider||p.value;ep.value=j.endpoint||"";model.value=j.model||"";key.value=j.key||"";mmEmail.value=j.mmEmail||"";mmKey.value=j.mmKey||"";fmt.value=j.format||fmt.value;uiLang.value=j.uiLang||"auto";lang=pickLang(uiLang.value);resident.checked=!!j.resident;startup.checked=!!j.startup;startMinimized.checked=!!j.startMinimized;lanAllowed=!!j.lan;syncStartup();preset(false);applyLang()}catch(e){syncStartup();applyLang()}}async function save(){clearTimeout(timer);syncStartup();const j={translate:trOn.checked,src:src.value,dst:dst.value,provider:p.value,endpoint:ep.value,model:model.value,key:key.value,mmEmail:mmEmail.value,mmKey:mmKey.value,format:fmt.value,uiLang:uiLang.value,resident:resident.checked,startup:startup.checked,startMinimized:startMinimized.checked,lan:lanAllowed};try{await fetch("/settings",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(j)})}catch(e){}}uiLang.addEventListener("change",()=>{applyLang();save()});trOn.addEventListener("change",()=>{showBoxes();save()});resident.addEventListener("change",()=>{syncStartup();save()});startup.addEventListener("change",()=>{syncStartup();save()});startMinimized.addEventListener("change",save);fmt.addEventListener("change",()=>{showBoxes();save()});p.addEventListener("change",()=>{preset(true);showBoxes();save()});[src,dst,ep,model,key,mmEmail,mmKey].forEach(x=>x.addEventListener("change",save));[key,ep,model,mmEmail,mmKey].forEach(x=>x.addEventListener("input",()=>{clearTimeout(timer);timer=setTimeout(save,600)}));async function tr(v){if(p.value!=="mymemory")return trAI(v);let u="https://api.mymemory.translated.net/get?q="+encodeURIComponent(v)+"&langpair="+encodeURIComponent(src.value+"|"+dst.value);if(mmEmail.value)u+="&de="+encodeURIComponent(mmEmail.value);if(mmKey.value)u+="&key="+encodeURIComponent(mmKey.value);let r=await fetch(u);let j=await r.json();return j.responseData&&j.responseData.translatedText?j.responseData.translatedText:""}function chatUrl(){let u=ep.value.trim().replace(/\/+$/,"");return u.endsWith("/chat/completions")?u:u+"/chat/completions"}async function trAI(v){if(!ep.value||!model.value||!key.value)throw Error("missing ai settings");let r=await fetch(chatUrl(),{method:"POST",headers:{"Content-Type":"application/json","Authorization":"Bearer "+key.value},body:JSON.stringify({model:model.value,messages:[{role:"system",content:"Translate the user text to "+dst.value+". Return only the translation."},{role:"user",content:v}]})});let j=await r.json();return j.choices&&j.choices[0]&&j.choices[0].message?j.choices[0].message.content:""}async function sendText(){const v=t.value.trim();if(!v){m.textContent=L("empty");m.className="m e";return}b.disabled=true;m.textContent=trOn.checked?L("translating"):L("sending");m.className="m";try{await save();let tv="",out="";if(trOn.checked&&fmt.value!=="orig"){tv=await tr(v)}if(trOn.checked&&fmt.value!=="orig"&&!tv){throw Error("empty trans")}if(trOn.checked){if(fmt.value==="trans")out=tv;else if(fmt.value==="orig")out=v;else out=v+"\n"+tv}else{out=v}const r=await fetch("/send",{method:"POST",headers:{"Content-Type":"text/plain;charset=utf-8"},body:out});if(!r.ok)throw Error();var h={hid:++hidCounter,text:v,trans:tv,payload:out,time:new Date().toLocaleTimeString()};history.unshift(h);prependHistoryItem(h);trimHistory();t.value="";cnt.textContent="0/144";cnt.style.color="#9ca3af";clearInterval(typingTimer);typingTimer=0;setTyping(false);m.textContent=trOn.checked?L("sentTrans"):L("sent");s.textContent=L("sentStatus")}catch(e){m.textContent=e.message==="missing ai settings"?L("missingAI"):e.message==="empty trans"?L("emptyTrans"):trOn.checked?L("transFail"):L("sendFail");m.className="m e";s.textContent=L("badConn")}finally{b.disabled=false;t.focus()}}t.addEventListener("keydown",e=>{if(e.key==="Enter"&&!e.shiftKey){e.preventDefault();sendText()}});t.addEventListener("input",function(){clearTimeout(timer);timer=setTimeout(function(){sendTyping()},300);if(t.value.trim()){if(!typingTimer)typingTimer=setInterval(sendTyping,5000)}else{clearInterval(typingTimer);typingTimer=0;setTyping(false)}var n=t.value.length;cnt.textContent=n+"/144";cnt.style.color=n>144?"#ef4444":"#9ca3af"});b.addEventListener("click",sendText);lanBtn.addEventListener("click",enableLan);clearBtn.addEventListener("click",function(){t.value="";t.focus();cnt.textContent="0/144";cnt.style.color="#9ca3af";clearInterval(typingTimer);typingTimer=0;setTyping(false)});function renderHistory(){hlist.innerHTML=history.map(function(h){return buildItemHTML(h)}).join("")}function findByHid(hid){for(var i=0;i<history.length;i++)if(history[i].hid===hid)return i;return -1}function buildItemHTML(h){return "<div class=\"hitem\" id=\"hitem-"+h.hid+"\" onpointerdown=\"startLongPress(event,"+h.hid+")\" onpointerup=\"endLongPress(event,"+h.hid+")\" onpointercancel=\"cancelLongPress()\" onpointerleave=\"cancelLongPress()\"><span class=\"htext\"><span class=\"hsrc\">"+h.text.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/\"/g,"&quot;")+"</span><span class=\"htrans\">"+(h.trans||"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/\"/g,"&quot;")+"</span></span><span class=\"htime\">"+h.time+"</span><span class=\"del\" onpointerdown=\"event.stopPropagation()\" onpointerup=\"event.stopPropagation()\" onclick=\"event.stopPropagation();delHistory("+h.hid+")\">&times;</span></div>"}function prependHistoryItem(h){hlist.insertAdjacentHTML("afterbegin",buildItemHTML(h))}function trimHistory(){while(history.length>maxHistory){var old=history.pop(),el=$("hitem-"+old.hid);if(el)el.remove()}}function startLongPress(e,hid){e.preventDefault();clearTimeout(longPressTimer);longPressFired=false;var el=$("hitem-"+hid);if(el)el.classList.add("pressing");longPressTimer=setTimeout(function(){longPressFired=true;if(el)el.classList.remove("pressing");resendFromHistory(hid)},600)}function endLongPress(e,hid){e.preventDefault();clearTimeout(longPressTimer);var el=$("hitem-"+hid);if(el)el.classList.remove("pressing");if(!longPressFired){var i=findByHid(hid);if(i>=0){t.value=history[i].text;t.focus();m.textContent=L("historyFilled");m.className="m"}}}function cancelLongPress(){clearTimeout(longPressTimer);var els=document.querySelectorAll(".hitem.pressing");for(var j=0;j<els.length;j++)els[j].classList.remove("pressing")}async function resendFromHistory(hid){var i=findByHid(hid);if(i<0)return;var h=history[i];b.disabled=true;m.textContent=L("resending");m.className="m";try{let out=h.payload||h.text;const r=await fetch("/send",{method:"POST",headers:{"Content-Type":"text/plain;charset=utf-8"},body:out});if(!r.ok)throw Error();m.textContent=L("resent");s.textContent=L("resentStatus")}catch(e){m.textContent=L("resendFail");m.className="m e";s.textContent=L("badConn")}finally{b.disabled=false}}function delHistory(hid){var i=findByHid(hid);if(i>=0)history.splice(i,1);var el=$("hitem-"+hid);if(el)el.remove()}syncStartup();applyLang();load();refreshLan();</script></body></html>'
html_len = $ - html

server_socket dd 0
client_socket dd 0
osc_socket dd 0
app_instance dd 0
tray_hwnd dd 0
tray_icon dd 0
tray_menu dd 0
tray_open_text dd 0
tray_exit_text dd 0
quit_requested dd 0
recv_len dd 0
session_count dd 0
shutdown_pending dd 0
ever_had_session dd 0
lan_enabled dd 0
lan_allowed dd 0
resident_mode dd 0
startup_mode dd 0
startup_minimized dd 0
idle_timeout dd 30000
now_tick dd 0
current_id rb 32
sessions rb session_slots * 32
last_seen rd session_slots
content_len dd 0
body_have dd 0
body_ptr dd 0
settings_handle dd 0
startup_key_handle dd 0
bytes_done dd 0
recv_timeout dd 2000
settings_write_len dd 0
startup_cmd_len dd 0
tmp_socket dd 0
sockaddr_len dd 16
accept_timeout dd 1000
readfds dd 0,0
select_timeout dd 1,0
hlist_ptr dd 0
best_ip_score dd 0
hostname rb 256
best_ip rb 16
tray_wc WNDCLASS
tray_nid NOTIFYICONDATAA
msg MSG
pt POINT

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
exe_path rb 260
startup_cmd rb 320
osc_packet rb 8192

section '.idata' import data readable writeable

library kernel32,'KERNEL32.DLL',\
        advapi32,'ADVAPI32.DLL',\
        user32,'USER32.DLL',\
        shell32,'SHELL32.DLL',\
        wsock32,'WSOCK32.DLL'

include '..\tools\fasm\include\api\kernel32.inc'
include '..\tools\fasm\include\api\user32.inc'
include '..\tools\fasm\include\api\shell32.inc'
include '..\tools\fasm\include\api\wsock32.inc'

import advapi32,\
       RegCloseKey,'RegCloseKey',\
       RegCreateKeyEx,'RegCreateKeyExA',\
       RegDeleteValue,'RegDeleteValueA',\
       RegOpenKeyEx,'RegOpenKeyExA',\
       RegSetValueEx,'RegSetValueExA'

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
