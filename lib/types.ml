open Base

(* Utilities *)

let test_bit_int32 x i =
  let open Int32 in
  x land (1l lsl i) <> 0l

let test_bit x i = x land (1 lsl i) <> 0

let set_bit x i = x lor (1 lsl i)

let set_bit_int32 x i =
  let open Int32 in
  x lor (1l lsl i)

let clear_bit x i = x land lnot (1 lsl i)

let clear_bit_int32 x i =
  let open Int32 in
  x land lnot (1l lsl i)

(* Constants *)

let frame_header_length = 9

let max_payload_length = Int.pow 2 14

(* Stream identifer *)

type stream_id = int32

(* Errors *)

type error_code = int32

type error_code_id =
  | NoError
  | ProtocolError
  | InternalError
  | FlowControlError
  | SettingsTimeout
  | StreamClosed
  | FrameSizeError
  | RefusedStream
  | Cancel
  | CompressionError
  | ConnectError
  | EnhanceYourCalm
  | InadequateSecurity
  | HTTP11Required
  | UnknownErrorCode of int32

let error_code_of_id = function
  | NoError -> 0x0l
  | ProtocolError -> 0x1l
  | InternalError -> 0x2l
  | FlowControlError -> 0x3l
  | SettingsTimeout -> 0x4l
  | StreamClosed -> 0x5l
  | FrameSizeError -> 0x6l
  | RefusedStream -> 0x7l
  | Cancel -> 0x8l
  | CompressionError -> 0x9l
  | ConnectError -> 0xal
  | EnhanceYourCalm -> 0xbl
  | InadequateSecurity -> 0xcl
  | HTTP11Required -> 0xdl
  | UnknownErrorCode x -> x

let error_code_to_id = function
  | 0x0l -> NoError
  | 0x1l -> ProtocolError
  | 0x2l -> InternalError
  | 0x3l -> FlowControlError
  | 0x4l -> SettingsTimeout
  | 0x5l -> StreamClosed
  | 0x6l -> FrameSizeError
  | 0x7l -> RefusedStream
  | 0x8l -> Cancel
  | 0x9l -> CompressionError
  | 0xal -> ConnectError
  | 0xbl -> EnhanceYourCalm
  | 0xcl -> InadequateSecurity
  | 0xdl -> HTTP11Required
  | w -> UnknownErrorCode w

type http2_error =
  | ConnectionError of error_code_id * string
  | StreamError of error_code_id * stream_id

let error_code_id_of_http = function
  | ConnectionError (err, _) -> err
  | StreamError (err, _) -> err

(** HTTP/2 Settings key *)

type settings_key_id =
  | SettingsHeaderTableSize
  | SettingsEnablePush
  | SettingsMaxConcurrentStreams
  | SettingsInitialWindowSize
  | SettingsMaxFrameSize
  | SettingsMaxHeaderListSize

type window_size = int

type settings_value = int

let settings_key_from_id = function
  | SettingsHeaderTableSize -> 0x1
  | SettingsEnablePush -> 0x2
  | SettingsMaxConcurrentStreams -> 0x3
  | SettingsInitialWindowSize -> 0x4
  | SettingsMaxFrameSize -> 0x5
  | SettingsMaxHeaderListSize -> 0x6

let settings_key_to_id = function
  | 0x1 -> Some SettingsHeaderTableSize
  | 0x2 -> Some SettingsEnablePush
  | 0x3 -> Some SettingsMaxConcurrentStreams
  | 0x4 -> Some SettingsInitialWindowSize
  | 0x5 -> Some SettingsMaxFrameSize
  | 0x6 -> Some SettingsMaxHeaderListSize
  | _ -> None

let default_initial_window_size = 65535

let max_window_size = 2147483647

let is_window_overflow w = test_bit w 31

type settings_list = (settings_key_id * settings_value) list

type settings =
  { header_table_size : int
  ; enable_push : bool
  ; max_concurrent_streams : int option
  ; initial_window_size : window_size
  ; max_frame_size : int
  ; max_header_list_size : int option }

let default_settings =
  { header_table_size = 4096
  ; enable_push = true
  ; max_concurrent_streams = None
  ; initial_window_size = default_initial_window_size
  ; max_frame_size = 16384
  ; max_header_list_size = None }

let check_settings_value = function
  | SettingsEnablePush, v ->
      if v <> 0 && v <> 1 then
        Some (ConnectionError (ProtocolError, "enable push must be 0 or 1"))
      else None
  | SettingsInitialWindowSize, v ->
      if v > 2147483647 then
        Some
          (ConnectionError
             (FlowControlError, "Window size must be less than or equal to 65535"))
      else None
  | SettingsMaxFrameSize, v ->
      if v < 16395 || v > 16777215 then
        Some
          (ConnectionError
             ( ProtocolError
             , "Max frame size must be in between 16384 and 16777215" ))
      else None
  | _ -> None

let check_settings_list settings =
  let results = List.filter_map ~f:check_settings_value settings in
  match results with [] -> None | x :: _ -> Some x

let update_settings settings kvs =
  let update settings = function
    | SettingsHeaderTableSize, v -> {settings with header_table_size = v}
    | SettingsEnablePush, v -> {settings with enable_push = v > 0}
    | SettingsMaxConcurrentStreams, v ->
        {settings with max_concurrent_streams = Some v}
    | SettingsInitialWindowSize, v -> {settings with initial_window_size = v}
    | SettingsMaxFrameSize, v -> {settings with max_frame_size = v}
    | SettingsMaxHeaderListSize, v ->
        {settings with max_header_list_size = Some v}
  in
  List.fold_left kvs ~init:settings ~f:update

type weight = int

type priority = {exclusive : bool; stream_dependency : stream_id; weight : weight}

let default_priority = {exclusive = false; stream_dependency = 0l; weight = 16}

let highest_priority = {exclusive = false; stream_dependency = 0l; weight = 256}

type padding = string

(* Raw HTTP/2 frame types *)

type frame_type = int

type frame_type_id =
  | FrameData
  | FrameHeaders
  | FramePriority
  | FrameRSTStream
  | FrameSettings
  | FramePushPromise
  | FramePing
  | FrameGoAway
  | FrameWindowUpdate
  | FrameContinuation
  | FrameUnknown of int

let frame_type_of_id = function
  | FrameData -> 0x0
  | FrameHeaders -> 0x1
  | FramePriority -> 0x2
  | FrameRSTStream -> 0x3
  | FrameSettings -> 0x4
  | FramePushPromise -> 0x5
  | FramePing -> 0x6
  | FrameGoAway -> 0x7
  | FrameWindowUpdate -> 0x8
  | FrameContinuation -> 0x9
  | FrameUnknown x -> x

let frame_type_to_id = function
  | 0x0 -> FrameData
  | 0x1 -> FrameHeaders
  | 0x2 -> FramePriority
  | 0x3 -> FrameRSTStream
  | 0x4 -> FrameSettings
  | 0x5 -> FramePushPromise
  | 0x6 -> FramePing
  | 0x7 -> FrameGoAway
  | 0x8 -> FrameWindowUpdate
  | 0x9 -> FrameContinuation
  | id -> FrameUnknown id

let frame_type_id_to_name = function
  | FrameData -> "DATA"
  | FrameHeaders -> "HEADERS"
  | FramePriority -> "PRIORITY"
  | FrameRSTStream -> "RST_STREAM"
  | FrameSettings -> "SETTINGS"
  | FramePushPromise -> "PUSH_PROMISE"
  | FramePing -> "PING"
  | FrameGoAway -> "GOAWAY"
  | FrameWindowUpdate -> "WINDOW_UPDATE"
  | FrameContinuation -> "CONTINUATION"
  | FrameUnknown _ -> "UNKNOWN"

(* Flags *)

type frame_flags = int

type flag_type =
  | FlagDataEndStream
  | FlagDataPadded
  | FlagHeadersEndStream
  | FlagHeadersEndHeaders
  | FlagHeadersPadded
  | FlagHeadersPriority
  | FlagSettingsAck
  | FlagPingAck
  | FlagContinuationEndHeaders
  | FlagPushPromiseEndHeaders
  | FlagPushPromisePadded

let has_flag t flag = t land flag = flag

let flag_type_to_id = function
  | FlagDataEndStream -> 0x1
  | FlagDataPadded -> 0x8
  | FlagHeadersEndStream -> 0x1
  | FlagHeadersEndHeaders -> 0x4
  | FlagHeadersPadded -> 0x8
  | FlagHeadersPriority -> 0x20
  | FlagSettingsAck -> 0x1
  | FlagPingAck -> 0x1
  | FlagContinuationEndHeaders -> 0x4
  | FlagPushPromiseEndHeaders -> 0x4
  | FlagPushPromisePadded -> 0x8

let flag_type_to_name = function
  | FlagDataEndStream -> "END_STREAM"
  | FlagDataPadded -> "PADDED"
  | FlagHeadersEndStream -> "END_STREAM"
  | FlagHeadersEndHeaders -> "END_HEADERS"
  | FlagHeadersPadded -> "PADDED"
  | FlagHeadersPriority -> "PRIORITY"
  | FlagSettingsAck -> "ACK"
  | FlagPingAck -> "ACK"
  | FlagContinuationEndHeaders -> "END_HEADERS"
  | FlagPushPromiseEndHeaders -> "END_HEADERS"
  | FlagPushPromisePadded -> "PADDED"

let flags_for_frame_type_id = function
  | FrameData -> [FlagDataEndStream; FlagDataPadded]
  | FrameHeaders ->
      [ FlagHeadersEndStream
      ; FlagHeadersEndHeaders
      ; FlagHeadersPadded
      ; FlagHeadersPriority ]
  | FrameSettings -> [FlagSettingsAck]
  | FramePing -> [FlagPingAck]
  | FrameContinuation -> [FlagContinuationEndHeaders]
  | FramePushPromise -> [FlagPushPromiseEndHeaders; FlagPushPromisePadded]
  | _ -> []

let default_flags = 0

let test_end_stream x = test_bit x 0

let test_ack x = test_bit x 0

let test_end_header x = test_bit x 2

let test_padded x = test_bit x 3

let test_priority x = test_bit x 5

let set_end_stream x = set_bit x 0

let set_ack x = set_bit x 0

let set_end_header x = set_bit x 2

let set_padded x = set_bit x 3

let set_priority x = set_bit x 5

(* Streams *)

let is_control id = Int32.(id = 0l)

let is_request id = Int32.(id % 2l = 1l)

let is_response id =
  let open Int32 in
  if id = 0l then false else id % 2l = 0l

let test_exclusive id = test_bit_int32 id 31

let set_exclusive id = set_bit_int32 id 31

let clear_exclusive id = clear_bit_int32 id 31

(* HTTP/2 frame types *)

type data_frame = string

type frame_header = {length : int; flags : frame_flags; stream_id : stream_id}

type frame_payload =
  | DataFrame of data_frame
  | HeadersFrame of priority option * string
  | PriorityFrame of priority
  | RSTStreamFrame of error_code_id
  | SettingsFrame of settings_list
  | PushPromiseFrame of stream_id * string
  | PingFrame of string
  | GoAwayFrame of stream_id * error_code_id * string
  | WindowUpdateFrame of window_size
  | ContinuationFrame of string
  | UnknownFrame of frame_type * string

let frame_payload_to_frame_id = function
  | DataFrame _ -> FrameData
  | HeadersFrame _ -> FrameHeaders
  | PriorityFrame _ -> FramePriority
  | RSTStreamFrame _ -> FrameRSTStream
  | SettingsFrame _ -> FrameSettings
  | PushPromiseFrame _ -> FramePushPromise
  | PingFrame _ -> FramePing
  | GoAwayFrame _ -> FrameGoAway
  | WindowUpdateFrame _ -> FrameWindowUpdate
  | ContinuationFrame _ -> FrameContinuation
  | UnknownFrame (x, _) -> FrameUnknown x

type frame = {frame_header : frame_header; frame_payload : frame_payload}

let is_padding_defined = function
  | DataFrame _ -> true
  | HeadersFrame _ -> true
  | PriorityFrame _ -> false
  | RSTStreamFrame _ -> false
  | SettingsFrame _ -> false
  | PushPromiseFrame _ -> true
  | PingFrame _ -> false
  | GoAwayFrame _ -> false
  | WindowUpdateFrame _ -> false
  | ContinuationFrame _ -> false
  | UnknownFrame _ -> false
