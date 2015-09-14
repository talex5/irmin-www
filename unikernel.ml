
(* Copyright (C) 2015, Thomas Leonard
 * See the README file for details. *)

open Lwt
open V1_LWT

let () = Log.(set_log_level INFO)

(* Never used, but needed to create the store. *)
let task s = Irmin.Task.create ~date:0L ~owner:"Server" s

module Store = Irmin.Basic(Irmin_mem.Make)(Irmin.Contents.String)

module Main (Stack:STACKV4) = struct
  module TCP  = Stack.TCPV4
  module S = Cohttp_mirage.Server(TCP)

  let handle_request _s _conn_id _request _body =
    S.respond_error ~status:`Method_not_allowed ~body:"Invalid request" ()

  let start stack =
    Store.create (Irmin_mem.config ()) task >>= fun s ->
    let http = S.make ~conn_closed:ignore ~callback:(handle_request s) () in
    Stack.listen_tcpv4 stack ~port:8080 (fun flow ->
      let peer, port = TCP.get_dest flow in
      Log.info "Connection from %s (client port %d)" (Ipaddr.V4.to_string peer) port;
      S.listen http flow >>= fun () ->
      TCP.close flow
    );
    Stack.listen stack
end
