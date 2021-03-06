open Core.Std
open Async.Std

let (^-) a b = a ^ "-" ^ b

let rpc ?(version = 0) (type q) (type r) ~name q r =
  let module Q = (val q : Binable.S with type t = q) in
  let module R = (val r : Binable.S with type t = r) in
  Rpc.Rpc.create ~name ~version ~bin_query:Q.bin_t ~bin_response:R.bin_t

let pipe_rpc ?(version = 0) (type q) (type r) (type e) ~name q r e =
  let module Q = (val q : Binable.S with type t = q) in
  let module R = (val r : Binable.S with type t = r) in
  let module E = (val e : Binable.S with type t = e) in
  Rpc.Pipe_rpc.create ~name ~version
    ~bin_query:Q.bin_t
    ~bin_response:R.bin_t
    ~bin_error:E.bin_t
    ()

let state_rpc ?(version = 0) (type q) (type s) (type u) (type e) ~name q s u e =
  let module Q = (val q : Binable.S with type t = q) in
  let module S = (val s : Binable.S with type t = s) in
  let module U = (val u : Binable.S with type t = u) in
  let module E = (val e : Binable.S with type t = e) in
  Rpc.State_rpc.create ~name ~version
    ~bin_query:Q.bin_t
    ~bin_state:S.bin_t
    ~bin_update:U.bin_t
    ~bin_error:E.bin_t
    ()

let or_error (type a) m
  : (module Binable.S with type t = a Or_error.t) =
  let module M = (val m : Binable.S with type t = a) in
  (module struct type t = M.t Or_error.t with bin_io end)

let list (type a) m
  : (module Binable.S with type t = a list) =
  let module M = (val m : Binable.S with type t = a) in
  (module struct type t = M.t list with bin_io end)

let option (type a) m
  : (module Binable.S with type t = a option) =
  let module M = (val m : Binable.S with type t = a) in
  (module struct type t = M.t option with bin_io end)

let pair (type a) (type b) (m1, m2)
  : (module Binable.S with type t = a * b) =
  let module M1 = (val m1 : Binable.S with type t = a) in
  let module M2 = (val m2 : Binable.S with type t = b) in
  (module struct type t = M1.t * M2.t with bin_io end)

let triple (type a) (type b) (type c) (m1, m2, m3)
  : (module Binable.S with type t = a * b * c) =
  let module M1 = (val m1 : Binable.S with type t = a) in
  let module M2 = (val m2 : Binable.S with type t = b) in
  let module M3 = (val m3 : Binable.S with type t = c) in
  (module struct type t = M1.t * M2.t * M3.t with bin_io end)

let binable (type a) m : (module Binable.S with type t = a) = m

let string       = binable (module String)
let int          = binable (module Int)
let unit         = binable (module Unit)
let bool         = binable (module Bool)
let time_span    = binable (module Time.Span)
let error        = binable (module Error)

let id           = binable (module Spool.Spooled_message_id)
let spool_status = binable (module Spool.Status)
let event        = binable (module Spool.Event)

let gc_stat      = binable (module Gc.Stat)
let pid          = binable (module Pid)

module Monitor = struct
  (* Including a sequence number. We broadcast a heartbeat message (with error =
     None) every 10 seconds..  *)
  let errors = pipe_rpc ~name:"errors" unit (pair (int, option error)) error
end

module Spool = struct
  let prefix = "spool"

  let status     = rpc ~name:(prefix ^- "status") unit spool_status

  let freeze     = rpc ~name:(prefix ^- "freeze") (list id) (or_error unit)
                     ~version:1

  let send_now   = rpc ~name:(prefix ^- "send-now")
                     (pair (list id, list time_span))
                     (or_error unit)

  let events     = pipe_rpc ~name:(prefix ^- "events") unit event error

  let set_max_concurrent_send_jobs =
    rpc ~name:(prefix ^- "set-max-send-jobs") int unit
end

module Gc = struct
  let stat       = rpc ~name:"gc-stat"       unit gc_stat
  let quick_stat = rpc ~name:"gc-quick-stat" unit gc_stat

  let full_major = rpc ~name:"gc-full-major" unit unit
  let major      = rpc ~name:"gc-major"      unit unit
  let minor      = rpc ~name:"gc-minor"      unit unit
  let compact    = rpc ~name:"gc-compact"    unit unit

  let stat_pipe  = pipe_rpc ~name:"gc-stat-pipe" unit gc_stat error
end

module Process = struct
  let pid        = rpc ~name:"proc-pid"      unit pid
end
