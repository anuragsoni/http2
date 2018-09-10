open Base
open Frames

module State = struct
  type peer = AwaitingHeaders | Streaming [@@deriving sexp]

  type cause = EndStream | LocallyReset of Types.error_code [@@deriving sexp]

  type t =
    | Idle
    | ReservedRemote
    | ReservedLocal
    | Open of {local : peer; remote : peer}
    | HalfClosedRemote of peer
    | HalfClosedLocal of peer
    | Closed of cause
  [@@deriving sexp]

  type state = {mutable value : t} [@@deriving sexp]

  let create = {value = Idle}

  let is_idle state = match state.value with Idle -> true | _ -> false

  let is_send_closed state =
    match state.value with
    | Closed _ | HalfClosedLocal _ | ReservedRemote -> true
    | _ -> false

  let is_recv_closed state =
    match state.value with
    | Closed _ | ReservedLocal | HalfClosedRemote _ -> true
    | _ -> false

  let is_closed state = match state.value with Closed _ -> true | _ -> false

  let is_recv_streaming state =
    match state.value with
    | Open {remote = Streaming; _} -> true
    | HalfClosedLocal Streaming -> true
    | _ -> false

  let can_recv_headers state =
    match state.value with
    | Idle -> true
    | Open {remote = AwaitingHeaders; _} -> true
    | HalfClosedLocal AwaitingHeaders -> true
    | ReservedRemote -> true
    | _ -> false

  let is_send_streaming state =
    match state.value with
    | Open {local = Streaming; _} -> true
    | HalfClosedRemote Streaming -> true
    | _ -> false

  let is_reset state =
    match state.value with
    | Closed EndStream -> false
    | Closed _ -> true
    | _ -> false

  let set_reset state reason = state.value <- Closed (LocallyReset reason)

  let send_close state =
    let new_state =
      match state.value with
      | Open {remote; _} -> Ok (HalfClosedLocal remote)
      | HalfClosedRemote _ -> Ok (Closed EndStream)
      | _ ->
          Error
            (Types.ConnectionError
               (Types.ProtocolError, "invalid action on state"))
    in
    Result.map ~f:(fun s -> state.value <- s) new_state

  let recv_close state =
    let new_state =
      match state.value with
      | Open {local; _} -> Ok (HalfClosedRemote local)
      | HalfClosedLocal _ -> Ok (Closed EndStream)
      | _ ->
          Error
            (Types.ConnectionError
               (Types.ProtocolError, "invalid action on state"))
    in
    Result.map ~f:(fun s -> state.value <- s) new_state

  let send_open state end_of_stream =
    let local = Streaming in
    let new_state =
      match state.value with
      | Idle ->
          Ok
            ( if end_of_stream then HalfClosedLocal AwaitingHeaders
            else Open {local; remote = AwaitingHeaders} )
      | Open {local = AwaitingHeaders; remote} ->
          Ok
            ( if end_of_stream then HalfClosedLocal remote
            else Open {local; remote} )
      | ReservedLocal ->
          Ok
            ( if end_of_stream then Closed EndStream
            else Open {local; remote = AwaitingHeaders} )
      | HalfClosedRemote AwaitingHeaders ->
          Ok (if end_of_stream then Closed EndStream else HalfClosedRemote local)
      | _ ->
          Error
            (Types.ConnectionError
               (Types.ProtocolError, "invalid action on state"))
    in
    Result.map ~f:(fun s -> state.value <- s) new_state

  let recv_open state end_of_stream =
    let remote = Streaming in
    let new_state =
      match state.value with
      | Idle ->
          Ok
            ( if end_of_stream then HalfClosedRemote AwaitingHeaders
            else Open {local = AwaitingHeaders; remote} )
      | ReservedRemote ->
          Ok
            ( if end_of_stream then Closed EndStream
            else Open {local = AwaitingHeaders; remote} )
      | Open {local; remote = AwaitingHeaders} ->
          Ok
            ( if end_of_stream then HalfClosedRemote local
            else Open {local; remote} )
      | HalfClosedLocal AwaitingHeaders ->
          Ok (if end_of_stream then Closed EndStream else HalfClosedLocal remote)
      | _ ->
          Error
            (Types.ConnectionError
               (Types.ProtocolError, "invalid action on state"))
    in
    Result.map ~f:(fun s -> state.value <- s) new_state

  let reserve_remote state =
    match state.value with
    | Idle ->
        state.value <- ReservedRemote ;
        Ok ()
    | _ ->
        Error
          (Types.ConnectionError (Types.ProtocolError, "invalid stream state"))

  let reserve_local state =
    match state.value with
    | Idle ->
        state.value <- ReservedLocal ;
        Ok ()
    | _ ->
        Error
          (Types.ConnectionError (Types.ProtocolError, "Invalid stream state"))

  let recv_reset state reason queued =
    match state.value with
    | Closed _ when not queued -> ()
    | _ -> state.value <- Closed (LocallyReset reason)
end