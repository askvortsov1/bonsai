open! Core
open! Import

let unit_type_id = Type_equal.Id.create ~name:"()" [%sexp_of: unit]
let nothing_type_id = Type_equal.Id.create ~name:"Nothing.t" [%sexp_of: Nothing.t]

module type Type_id = sig
  type 'a t [@@deriving sexp_of]

  val same_witness : 'a t -> 'b t -> ('a, 'b) Type_equal.t option
  val same_witness_exn : 'a t -> 'b t -> ('a, 'b) Type_equal.t
  val to_type_id : 'a t -> 'a Type_equal.Id.t
  val to_sexp : 'a t -> 'a -> Sexp.t
  val nothing : Nothing.t t
  val unit : unit t
end

module Model = struct
  type 'a id =
    | Leaf : { type_id : 'a Type_equal.Id.t } -> 'a id
    | Tuple :
        { a : 'a id
        ; b : 'b id
        }
        -> ('a * 'b) id
    | Tuple3 :
        { a : 'a id
        ; b : 'b id
        ; c : 'c id
        }
        -> ('a * 'b * 'c) id
    | Either :
        { a : 'a id
        ; b : 'b id
        }
        -> ('a, 'b) Either.t id
    | Map :
        { k : 'k Type_equal.Id.t
        ; cmp : 'cmp Type_equal.Id.t
        ; by : 'result id
        }
        -> ('k, 'result, 'cmp) Map.t id
    | Map_on :
        { k_model : 'k_model Type_equal.Id.t
        ; k_io : 'k_io Type_equal.Id.t
        ; cmp : 'cmp_model Type_equal.Id.t
        ; by : 'result id
        }
        -> ('k_model, 'k_io * 'result, 'cmp_model) Map.t id
    | Multi_model : { multi_model : hidden Int.Map.t } -> hidden Int.Map.t id

  and 'a t =
    { default : 'a
    ; equal : 'a -> 'a -> bool
    ; type_id : 'a id
    ; sexp_of : 'a -> Sexp.t
    ; of_sexp : Sexp.t -> 'a
    }

  and hidden =
    | T :
        { model : 'm
        ; info : 'm t
        ; t_of_sexp : Sexp.t -> hidden
        }
        -> hidden

  module Type_id = struct
    type 'a t = 'a id

    let rec sexp_of_t : type a. (a -> Sexp.t) -> a t -> Sexp.t =
      fun sexp_of_a -> function
        | Leaf { type_id } -> [%sexp (type_id : a Type_equal.Id.t)]
        | Tuple { a; b } -> [%sexp (a : opaque t), (b : opaque t)]
        | Tuple3 { a; b; c } -> [%sexp (a : opaque t), (b : opaque t), (c : opaque t)]
        | Either { a; b; _ } -> [%sexp Either, (a : opaque t), (b : opaque t)]
        | Map { by; _ } -> [%sexp (by : opaque t)]
        | Map_on { by; _ } -> [%sexp (by : opaque t)]
        | Multi_model { multi_model } ->
          let sexp_of_hidden (T { info = { type_id; _ }; _ }) =
            [%sexp (type_id : opaque t)]
          in
          [%sexp (multi_model : hidden Int.Map.t)]
    ;;

    let rec to_sexp : type a. a t -> a -> Sexp.t = function
      | Leaf { type_id } -> Type_equal.Id.to_sexp type_id
      | Tuple { a = a_t; b = b_t } ->
        let sexp_of_a = to_sexp a_t in
        let sexp_of_b = to_sexp b_t in
        [%sexp_of: a * b]
      | Tuple3 { a = a_t; b = b_t; c = c_t } ->
        let sexp_of_a = to_sexp a_t in
        let sexp_of_b = to_sexp b_t in
        let sexp_of_c = to_sexp c_t in
        [%sexp_of: a * b * c]
      | Either { a = a_t; b = b_t } ->
        let sexp_of_a = to_sexp a_t in
        let sexp_of_b = to_sexp b_t in
        [%sexp_of: (a, b) Either.t]
      | Map { k; by; _ } ->
        let result : type k by. k Type_equal.Id.t -> by id -> (k, by, _) Map.t -> Sexp.t =
          fun k by ->
            let module Key = struct
              type t = k

              let sexp_of_t : t -> Sexp.t = Type_equal.Id.to_sexp k
            end
            in
            let sexp_of_by = to_sexp by in
            [%sexp_of: by Map.M(Key).t]
        in
        result k by
      | Map_on { k_model; k_io; by; _ } ->
        let result (type k_model) (k_model : k_model Type_equal.Id.t) k_io by =
          let module Key = struct
            type t = k_model

            let sexp_of_t : t -> Sexp.t = Type_equal.Id.to_sexp k_model
          end
          in
          let sexp_of_by = to_sexp by in
          let sexp_of_k_io = Type_equal.Id.to_sexp k_io in
          [%sexp_of: (k_io * by) Map.M(Key).t]
        in
        result k_model k_io by
      | Multi_model _ ->
        let sexp_of_hidden (T { info = { type_id; _ }; _ }) =
          sexp_of_t sexp_of_opaque type_id
        in
        [%sexp_of: hidden Int.Map.t]
    ;;

    exception Fail

    let type_equal_id_same_witness_exn
      : type a b. a Type_equal.Id.t -> b Type_equal.Id.t -> (a, b) Type_equal.t
      =
      fun a b ->
      match Type_equal.Id.same_witness a b with
      | Some T -> Type_equal.T
      | None -> raise_notrace Fail
    ;;

    let rec same_witness_exn : type a b. a t -> b t -> (a, b) Type_equal.t =
      fun a b ->
        match a, b with
        | Leaf a, Leaf b ->
          let T = type_equal_id_same_witness_exn a.type_id b.type_id in
          (Type_equal.T : (a, b) Type_equal.t)
        | Tuple a, Tuple b ->
          let T = same_witness_exn a.a b.a in
          let T = same_witness_exn a.b b.b in
          (Type_equal.T : (a, b) Type_equal.t)
        | Tuple3 a, Tuple3 b ->
          let T = same_witness_exn a.a b.a in
          let T = same_witness_exn a.b b.b in
          let T = same_witness_exn a.c b.c in
          (Type_equal.T : (a, b) Type_equal.t)
        | Either a, Either b ->
          let T = same_witness_exn a.a b.a in
          let T = same_witness_exn a.b b.b in
          (Type_equal.T : (a, b) Type_equal.t)
        | Map a, Map b ->
          let T = type_equal_id_same_witness_exn a.k b.k in
          let T = type_equal_id_same_witness_exn a.cmp b.cmp in
          let T = same_witness_exn a.by b.by in
          (Type_equal.T : (a, b) Type_equal.t)
        | Map_on a, Map_on b ->
          let T = type_equal_id_same_witness_exn a.k_io b.k_io in
          let T = type_equal_id_same_witness_exn a.k_model b.k_model in
          let T = type_equal_id_same_witness_exn a.cmp b.cmp in
          let T = same_witness_exn a.by b.by in
          (Type_equal.T : (a, b) Type_equal.t)
        | Multi_model a, Multi_model b ->
          Map.iter2 a.multi_model b.multi_model ~f:(fun ~key:_ ~data ->
            match data with
            | `Both (T a, T b) ->
              let T = same_witness_exn a.info.type_id b.info.type_id in
              ()
            | _ -> raise_notrace Fail);
          Type_equal.T
        | Leaf _, Tuple _
        | Leaf _, Tuple3 _
        | Leaf _, Either _
        | Leaf _, Map _
        | Leaf _, Map_on _
        | Leaf _, Multi_model _
        | Tuple _, Leaf _
        | Tuple _, Tuple3 _
        | Tuple _, Either _
        | Tuple _, Map _
        | Tuple _, Map_on _
        | Tuple _, Multi_model _
        | Tuple3 _, Leaf _
        | Tuple3 _, Tuple _
        | Tuple3 _, Either _
        | Tuple3 _, Map _
        | Tuple3 _, Map_on _
        | Tuple3 _, Multi_model _
        | Either _, Leaf _
        | Either _, Tuple _
        | Either _, Tuple3 _
        | Either _, Map _
        | Either _, Map_on _
        | Either _, Multi_model _
        | Map _, Leaf _
        | Map _, Tuple _
        | Map _, Tuple3 _
        | Map _, Either _
        | Map _, Map_on _
        | Map _, Multi_model _
        | Map_on _, Leaf _
        | Map_on _, Tuple _
        | Map_on _, Tuple3 _
        | Map_on _, Either _
        | Map_on _, Map _
        | Map_on _, Multi_model _
        | Multi_model _, Leaf _
        | Multi_model _, Tuple _
        | Multi_model _, Tuple3 _
        | Multi_model _, Either _
        | Multi_model _, Map _
        | Multi_model _, Map_on _ -> raise_notrace Fail
    ;;

    let same_witness a b =
      match same_witness_exn a b with
      | exception Fail -> None
      | proof -> Some proof
    ;;

    let to_type_id _ = Type_equal.Id.create ~name:"module tree type id" [%sexp_of: opaque]
    let unit = Leaf { type_id = unit_type_id }
    let nothing = Leaf { type_id = nothing_type_id }
  end

  let unit =
    { type_id = Type_id.unit
    ; default = ()
    ; equal = equal_unit
    ; sexp_of = sexp_of_unit
    ; of_sexp = unit_of_sexp
    }
  ;;

  let both model1 model2 =
    let sexp_of = Tuple2.sexp_of_t model1.sexp_of model2.sexp_of in
    let of_sexp = Tuple2.t_of_sexp model1.of_sexp model2.of_sexp in
    let type_id = Tuple { a = model1.type_id; b = model2.type_id } in
    let default = model1.default, model2.default in
    let equal = Tuple2.equal ~eq1:model1.equal ~eq2:model2.equal in
    { type_id; default; equal; sexp_of; of_sexp }
  ;;

  let map
        (type k cmp)
        (module M : Comparator with type t = k and type comparator_witness = cmp)
        k
        cmp
        model
    =
    let sexp_of_model = model.sexp_of in
    let model_of_sexp = model.of_sexp in
    let sexp_of_map_model = [%sexp_of: model Map.M(M).t] in
    let model_map_type_id = Map { k; cmp; by = model.type_id } in
    { type_id = model_map_type_id
    ; default = Map.empty (module M)
    ; equal = Map.equal model.equal
    ; sexp_of = sexp_of_map_model
    ; of_sexp = [%of_sexp: model Map.M(M).t]
    }
  ;;

  let map_on
        (type k cmp k_io cmp_io)
        (module M : Comparator with type t = k and type comparator_witness = cmp)
        (module M_io : Comparator with type t = k_io and type comparator_witness = cmp_io)
        k_model
        k_io
        cmp
        model
    =
    let sexp_of_model = model.sexp_of in
    let model_of_sexp = model.of_sexp in
    let sexp_of_map_model = [%sexp_of: (M_io.t * model) Map.M(M).t] in
    let model_map_type_id = Map_on { k_model; k_io; cmp; by = model.type_id } in
    let io_equal a b = M_io.comparator.compare a b = 0 in
    { type_id = model_map_type_id
    ; default = Map.empty (module M)
    ; equal = Map.equal (Tuple2.equal ~eq1:io_equal ~eq2:model.equal)
    ; sexp_of = sexp_of_map_model
    ; of_sexp = [%of_sexp: (M_io.t * model) Map.M(M).t]
    }
  ;;

  let of_module (type t) (module M : Model with type t = t) ~default ~name =
    let type_id = Type_equal.Id.create ~name:(sprintf "%s-model" name) M.sexp_of_t in
    { type_id = Leaf { type_id }
    ; default
    ; equal = M.equal
    ; sexp_of = M.sexp_of_t
    ; of_sexp = M.t_of_sexp
    }
  ;;

  module Hidden = struct
    type 'a model = 'a t

    type t = hidden =
      | T :
          { model : 'm
          ; info : 'm model
          ; t_of_sexp : Sexp.t -> hidden
          }
          -> t

    let sexp_of_t (T { model; info = { sexp_of; _ }; _ }) = sexp_of model

    let equal
          (T { model = m1; info = { type_id = t1; equal; _ }; _ })
          (T { model = m2; info = { type_id = t2; _ }; _ })
      =
      match Type_id.same_witness t1 t2 with
      | Some T -> equal m1 m2
      | None -> false
    ;;

    let create (info : _ model) =
      let rec t_of_sexp sexp = wrap (info.of_sexp sexp)
      and wrap m = T { model = m; info; t_of_sexp } in
      wrap
    ;;

    let lazy_ =
      { default = None
      ; equal = [%equal: t option]
      ; type_id =
          Leaf { type_id = Type_equal.Id.create ~name:"lazy-model" [%sexp_of: t option] }
      ; sexp_of = [%sexp_of: t option]
      ; of_sexp = Fn.const None
      }
    ;;
  end
end

module Action = struct
  module Type_id = Model.Type_id

  type 'a t = 'a Type_id.t

  module Hidden = struct
    type 'a action = 'a t

    type 'key t =
      | T :
          { action : 'a
          ; type_id : 'a action
          ; key : 'key
          }
          -> 'key t

    let sexp_of_t sexp_of_key (T { type_id; key; _ }) =
      let sexp_of_action = Type_id.sexp_of_t sexp_of_opaque in
      [%message "enum action with key" (type_id : action) (key : key)]
    ;;

    let action_id sexp_of_key =
      Model.Leaf
        { type_id = Type_equal.Id.create ~name:"enum action with key" [%sexp_of: key t] }
    ;;

    let unit = action_id [%sexp_of: unit]
    let int = action_id [%sexp_of: int]
  end

  let nothing = Type_id.nothing
  let both a b = Model.Either { a; b }
  let map k action = Model.Tuple { a = Leaf { type_id = k }; b = action }

  let map_for_assoc_on io_k model_k action =
    Model.Tuple3
      { a = Leaf { type_id = io_k }; b = Leaf { type_id = model_k }; c = action }
  ;;

  let of_module (type t) (module M : Action with type t = t) ~name =
    Model.Leaf
      { type_id = Type_equal.Id.create ~name:(sprintf "%s-action" name) M.sexp_of_t }
  ;;
end

module Multi_model = struct
  type t = Model.Hidden.t Int.Map.t

  let sexp_of_t (type k) (sexp_of_k : k -> Sexp.t) =
    let module K = struct
      type t = k [@@deriving sexp_of]
    end
    in
    [%sexp_of: Model.Hidden.t Map.M(K).t]
  ;;

  let t_of_sexp (default_models : t) sexp =
    let k_to_sexp_map = [%of_sexp: Sexp.t Int.Map.t] sexp in
    Map.merge k_to_sexp_map default_models ~f:(fun ~key:_ -> function
      | `Both (sexp, Model.Hidden.T { t_of_sexp; _ }) -> Some (t_of_sexp sexp)
      | `Left _sexp -> None
      | `Right default_model -> Some default_model)
  ;;

  let find_exn = Map.find_exn
  let set = Map.set
  let to_models, of_models = Fn.id, Fn.id

  let model_info default =
    let sexp_of = [%sexp_of: int t] in
    let of_sexp = t_of_sexp default in
    let type_id = Model.Multi_model { multi_model = default } in
    ({ default; type_id; equal = [%equal: Model.Hidden.t Int.Map.t]; sexp_of; of_sexp }
     : t Model.t)
  ;;
end
