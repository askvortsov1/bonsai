open! Core
open Bonsai_web

module Error_details : sig
  type t =
    { error : Error.t
    ; on_mouse_over : unit Ui_effect.t
    ; on_mouse_out : unit Ui_effect.t
    ; on_click : unit Ui_effect.t
    ; is_viewing : bool
    ; is_toggled : bool
    }

  val background_color_var : string
  val toggled_border_color_var : string
  val untoggled_border_color_var : string
end

module Row : sig
  type t =
    { label : Vdom.Node.t option
    ; tooltip : Vdom.Node.t option
    ; form : Vdom.Node.t
    ; id : string
    ; error : Error_details.t option
    }
end

type t =
  | Empty
  | Row of Row.t
  | List of t list
  | Group of
      { label : Vdom.Node.t option
      ; tooltip : Vdom.Node.t option
      ; error : Error_details.t option
      ; view : t
      }
  | Header_group of
      { label : Vdom.Node.t option
      ; tooltip : Vdom.Node.t option
      ; error : Error_details.t option
      ; header_view : t
      ; view : t
      }
  | Submit_button of
      { text : string
      ; attr : Vdom.Attr.t
      ; (* none implies that the button is disabled *)
        on_submit : unit Ui_effect.t option
      }

val suggest_error : Error_details.t -> t -> t
val set_label : Vdom.Node.t -> t -> t
val set_tooltip : Vdom.Node.t -> t -> t
val group : Vdom.Node.t -> t -> t
val group_list : t -> t
val suggest_label : Vdom.Node.t -> t -> t
val of_vdom : id:string -> Vdom.Node.t -> t
val concat : t -> t -> t
val view_error : Error.t -> Vdom.Node.t list
val view_error_details : Error_details.t -> Vdom.Node.t

val wrap_tooltip_and_error
  :  tooltip:Vdom.Node.t option
  -> error:Error_details.t option
  -> Vdom.Node.t

type submission_options =
  { on_submit : unit Ui_effect.t option
  ; handle_enter : bool
  ; button_text : string option
  ; button_attr : Vdom.Attr.t
  }

type editable =
  [ `Yes_always
  | `Currently_yes
  | `Currently_no
  ]

val with_fieldset : currently_editable:bool -> Vdom.Node.t -> Vdom.Node.t
val to_vdom : ?on_submit:submission_options -> ?editable:editable -> t -> Vdom.Node.t
val to_vdom_plain : t -> Vdom.Node.t list
val sexp_to_pretty_string : ('a -> Sexp.t) -> 'a -> string
