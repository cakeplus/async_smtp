open Core.Std
open Async.Std
open Async_smtp.Std

let config =
 { Smtp_server.Config.
   spool_dir = "/tmp/spool-mailcore"
 ; tmp_dir = None
 ; ports = [ 2200; 2201 ]
 ; max_concurrent_send_jobs = 1
 ; max_concurrent_receive_jobs_per_port = 1
 ; rpc_port = 2210
 ; malformed_emails = `Reject
 ; max_message_size = Byte_units.create `Megabytes 1.
 ; tls_options =
     Some
       { Smtp_server.Config.Tls.
         version = None
       ; name = None
       ; crt_file = "/tmp/mailcore.crt"
       ; key_file = "/tmp/mailcore.key"
       ; ca_file = None
       ; ca_path  = None
       }
 ; client = Smtp_client.Config.default
 }

module Callbacks = struct
  include Smtp_server.Callbacks.Simple

  let destination =
    Host_and_port.create ~host:"localhost" ~port:26

  let process_envelope ~session:_ envelope =
    return (`Send
              [ Smtp_envelope_with_next_hop.create
                  ~envelope
                  ~next_hop_choices:[destination]
                  ~retry_intervals:[]
              ])
end

let main () =
  let spool_dir = Smtp_server.Config.spool_dir config in
  Log.Global.info "creating %s" spool_dir;
  Unix.mkdir ~p:() spool_dir
  >>= fun () ->
  Smtp_server.start ~config (module Callbacks : Smtp_server.Callbacks.S)
  >>| Or_error.ok_exn
  >>= fun server ->
  let ports =
    Smtp_server.Config.ports config
    |> List.map ~f:Int.to_string
    |> String.concat ~sep:", "
  in
  Log.Global.info "mailcore listening on ports %s" ports;
  Shutdown.set_default_force Deferred.never;
  Shutdown.at_shutdown (fun () ->
    Smtp_server.close ~timeout:(Clock.after (sec 60.)) server
    >>| Or_error.ok_exn);
  Deferred.never ()
;;

let run () =
  don't_wait_for (main ());
  never_returns (Scheduler.go ())
;;

run ()
