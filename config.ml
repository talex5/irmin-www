(* Copyright (C) 2015, Thomas Leonard
 * See the README file for details. *)

open Mirage

let net =
  match get_mode () with
  | `Xen -> `Direct
  | `Unix ->
      try match Sys.getenv "NET" with
        | "direct" -> `Direct
        | "socket" -> `Socket
        | _        -> `Direct
      with Not_found -> `Socket

let ipv4_conf =
  let i = Ipaddr.V4.of_string_exn in
  {
    address  = i "10.0.0.2";
    netmask  = i "255.255.255.0";
    gateways = [i "10.0.0.1"];
  }

let stack console =
  match net with
  | `Socket -> socket_stackv4 console [Ipaddr.V4.any]
  | `Direct ->
      try match Sys.getenv "DHCP" with
        | "no" -> direct_stackv4_with_static_ipv4 console tap0 ipv4_conf
        | "yes" -> direct_stackv4_with_dhcp console tap0
        | _ -> raise Not_found
      with Not_found -> failwith "Set DHCP to 'yes' or 'no'"

let main =
  let libraries = ["irmin.git"; "mirage-http"; "irmin.mirage"; "tls.mirage"] in
  let libraries = if get_mode () = `Xen then libraries else "irmin.unix" :: libraries in
  foreign
    ~libraries
    ~packages:["irmin"; "mirage-http"; "nocrypto"; "mirage-flow"; "tls"; "nocrypto";
               "mirage-types-lwt"; "channel"; "git"; "mirage-git"]
    "Unikernel.Main" (stackv4 @-> kv_ro @-> clock @-> job)

let conf = crunch "conf"

let () =
  register "irmin-www" [
    main $ stack default_console $ conf $ default_clock
  ]
