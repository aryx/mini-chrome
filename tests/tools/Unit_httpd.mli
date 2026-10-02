(* mini-httpd's answers (tools/httpd's Httpd): Httpd.mli's worked
 * example, on a temporary directory, no socket; and its WebSocket
 * echo, by Websocket_client on a server forked *)
val tests : < Cap.open_in ; Cap.network ; .. > -> Testo.t list
