%{
  open Types

  type literal_reading_state = Normal | ReadingSpace
  type range_kind =
    | Tok       of Range.t
    | TokArg    of (Range.t * string)
    | Untyped   of untyped_abstract_tree
    | Pat       of untyped_pattern_tree
    | Rng       of Range.t
    | ManuType  of manual_type
    | VarntCons of untyped_variant_cons


  let make_range (sttx : range_kind) (endx : range_kind) =
    let extract x =
      match x with
      | Tok(rng)            -> rng
      | TokArg((rng, _))    -> rng
      | Untyped((rng, _))   -> rng
      | Pat((rng, _))       -> rng
      | Rng(rng)            -> rng
      | VarntCons((rng, _)) -> rng
      | ManuType((rng, _))  -> rng
    in
      Range.unite (extract sttx) (extract endx)


  let end_header : untyped_abstract_tree = (Range.dummy "end_header", UTFinishHeaderFile)

  let end_struct (rng : Range.t) : untyped_abstract_tree = (rng, UTFinishStruct)

  let end_of_argument_variable : untyped_argument_variable_cons = []

  let end_of_argument : untyped_argument_cons = []

  let end_of_mutual_let : untyped_mutual_let_cons = []


  let rec append_argument_list (arglsta : untyped_argument_cons) (arglstb : untyped_argument_cons) =
    List.append arglsta arglstb


  let class_and_id_region (utast : untyped_abstract_tree) =
    (Range.dummy "class_and_id_region", UTClassAndIDRegion(utast))


  let convert_into_apply (csutast : untyped_abstract_tree) (clsnmutast : untyped_abstract_tree)
                               (idnmutast : untyped_abstract_tree) (argcons : untyped_argument_cons) =
    let (csrng, _) = csutast in
    let rec iter argcons utastconstr =
      match argcons with
      | []                          -> utastconstr
      | (argrng, argmain) :: actail -> iter actail (Range.unite csrng argrng, UTApply(utastconstr, (argrng, argmain)))
    in
      iter argcons (Range.dummy "convert_into_apply", UTApplyClassAndID(clsnmutast, idnmutast, csutast))


  let class_name_to_abstract_tree (clsnm : class_name) =
    UTConstructor("Just", (Range.dummy "class_name_to", UTStringConstant((String.sub clsnm 1 ((String.length clsnm) - 1)))))


  let id_name_to_abstract_tree (idnm : id_name) =
    UTConstructor("Just", (Range.dummy "id_name_to", UTStringConstant((String.sub idnm 1 ((String.length idnm) - 1)))))


  let rec curry_lambda_abstract (rng : Range.t) (argvarcons : untyped_argument_variable_cons) (utastdef : untyped_abstract_tree) =
    match argvarcons with
    | []                                     -> utastdef
    | (varrng, UTPVariable(varnm)) :: avtail ->
        (rng, UTLambdaAbstract(varrng, varnm, curry_lambda_abstract rng avtail utastdef))
    | (varrng, UTPWildCard) :: avtail        ->
        (rng, UTLambdaAbstract(varrng, "%wild", curry_lambda_abstract rng avtail utastdef))
    | (varrng, argpatas) :: avtail           ->
        let afterabs     = curry_lambda_abstract rng avtail utastdef in
        let dummyutast   = (varrng, UTContentOf([], "%patarg")) in
        let dummypatcons = UTPatternMatchCons((varrng, argpatas), afterabs, UTEndOfPatternMatch) in
          (rng, UTLambdaAbstract(varrng, "%patarg", (varrng, UTPatternMatch(dummyutast, dummypatcons))))


  let rec stringify_literal ltrl =
    let (_, ltrlmain) = ltrl in
      match ltrlmain with
      | UTConcat(utastf, utastl) -> (stringify_literal utastf) ^ (stringify_literal utastl)
      | UTStringConstant(s)      -> s
      | UTStringEmpty            -> ""
      | _                        -> assert false

  let rec omit_pre_spaces str =
    let len = String.length str in
      if len = 0 then "" else
        match String.sub str 0 1 with
        | " " -> omit_pre_spaces (String.sub str 1 (len - 1)) 
        | _   -> str

  let rec omit_post_spaces str =
    let len = String.length str in
      if len = 0 then "" else
        match String.sub str (len - 1) 1 with
        | " "  -> omit_post_spaces (String.sub str 0 (len - 1))
        | "\n" -> String.sub str 0 (len - 1)
        | _    -> str


  let rec omit_spaces (ltrl : untyped_abstract_tree) =
    let str_ltrl = omit_post_spaces (omit_pre_spaces (stringify_literal ltrl)) in
      let min_indent = min_indent_space str_ltrl in
        let str_shaved = shave_indent str_ltrl min_indent in
        let len_shaved = String.length str_shaved in
          if len_shaved >= 1 && str_shaved.[len_shaved - 1] = '\n' then
            let str_no_last_break = String.sub str_shaved 0 (len_shaved - 1) in
              UTConcat(
                (Range.dummy "omit_spaces1", UTStringConstant(str_no_last_break)),
                (Range.dummy "omit_spaces2", UTBreakAndIndent)
              )
          else
            UTStringConstant(str_shaved)


  and min_indent_space (str_ltrl : string) =
    min_indent_space_sub str_ltrl 0 ReadingSpace 0 (String.length str_ltrl)


  and min_indent_space_sub (str_ltrl : string) (index : int) (lrstate : literal_reading_state) (spnum : int) (minspnum : int) =
    if index >= (String.length str_ltrl) then
        minspnum
    else
      match lrstate with
      | Normal ->
          ( match str_ltrl.[index] with
            | '\n' -> min_indent_space_sub str_ltrl (index + 1) ReadingSpace 0 minspnum
            | _    -> min_indent_space_sub str_ltrl (index + 1) Normal 0 minspnum
          )
      | ReadingSpace ->
          ( match str_ltrl.[index] with
            | ' '  -> min_indent_space_sub str_ltrl (index + 1) ReadingSpace (spnum + 1) minspnum
            | '\n' -> min_indent_space_sub str_ltrl (index + 1) ReadingSpace 0 minspnum
                (* does not take space-only line into account *)
            | _    -> min_indent_space_sub str_ltrl (index + 1) Normal 0 (if spnum < minspnum then spnum else minspnum)
          )

  and shave_indent str_ltrl minspnum =
    shave_indent_sub str_ltrl minspnum 0 "" Normal 0

  and shave_indent_sub str_ltrl minspnum index str_constr lrstate spnum =
    if index >= (String.length str_ltrl) then
      str_constr
    else
      match lrstate with
      | Normal ->
          begin
            match str_ltrl.[index] with
            | '\n' -> shave_indent_sub str_ltrl minspnum (index + 1) (str_constr ^ "\n") ReadingSpace 0
            | ch   -> shave_indent_sub str_ltrl minspnum (index + 1) (str_constr ^ (String.make 1 ch)) Normal 0
          end
      | ReadingSpace ->
          begin
            match str_ltrl.[index] with
            | ' ' ->
                if spnum < minspnum then
                  shave_indent_sub str_ltrl minspnum (index + 1) str_constr ReadingSpace (spnum + 1)
                else
                  shave_indent_sub str_ltrl minspnum (index + 1) (str_constr ^ " ") ReadingSpace (spnum + 1)

            | '\n' -> shave_indent_sub str_ltrl minspnum (index + 1) (str_constr ^ "\n") ReadingSpace 0
            | ch   -> shave_indent_sub str_ltrl minspnum (index + 1) (str_constr ^ (String.make 1 ch)) Normal 0
          end

  let extract_main (_, utastmain) = utastmain


  let extract_name (_, name) = name


  let binary_operator (opname : var_name) (utastl : untyped_abstract_tree) (oprng : Range.t) (utastr : untyped_abstract_tree) : untyped_abstract_tree =
    let rng = make_range (Untyped utastl) (Untyped utastr) in
      (rng, UTApply((Range.dummy "binary_operator", UTApply((oprng, UTContentOf([], opname)), utastl)), utastr))


  let make_standard (sttknd : range_kind) (endknd : range_kind) (main : 'a) =
    let rng = make_range sttknd endknd in (rng, main)


  let make_let_expression (lettk : Range.t) (decs : untyped_mutual_let_cons) (utastaft : untyped_abstract_tree) =
    make_standard (Tok lettk) (Untyped utastaft) (UTLetIn(decs, utastaft))


  let make_let_mutable_expression
      (letmuttk : Range.t) (vartk : Range.t * var_name)
      (utastdef : untyped_abstract_tree) (utastaft : untyped_abstract_tree)
  : untyped_abstract_tree
  =
    let (varrng, varnm) = vartk in
      make_standard (Tok letmuttk) (Untyped utastaft) (UTLetMutableIn(varrng, varnm, utastdef, utastaft))


  let make_variant_declaration (firsttk : Range.t) (varntdecs : untyped_mutual_variant_cons) (utastaft : untyped_abstract_tree) : untyped_abstract_tree =
    make_standard (Tok firsttk) (Untyped utastaft) (UTDeclareVariantIn(varntdecs, utastaft))


  let make_mutual_let_cons
      (mntyopt : manual_type option)
      (vartk : Range.t * var_name) (argcons : untyped_argument_variable_cons) (utastdef : untyped_abstract_tree)
      (tailcons : untyped_mutual_let_cons)
  : untyped_mutual_let_cons
  =
    let (varrng, varnm) = vartk in
    let curried = curry_lambda_abstract varrng argcons utastdef in
      (mntyopt, varnm, curried) :: tailcons


  let rec make_mutual_let_cons_par
      (mntyopt : manual_type option)
      (vartk : Range.t * var_name) (argletpatcons : untyped_let_pattern_cons)
      (tailcons : untyped_mutual_let_cons)
  : untyped_mutual_let_cons
  =
    let (_, varnm) = vartk in
    let pmcons  = make_pattern_match_cons_of_argument_pattern_cons argletpatcons in
    let fullrng = get_range_of_let_pattern_cons argletpatcons in
    let abs     = make_lambda_abstract_for_parallel fullrng argletpatcons pmcons in
      (mntyopt, varnm, abs) :: tailcons


  and get_range_of_let_pattern_cons (argletpatcons : untyped_let_pattern_cons) : Range.t =
    let get_first_range argletpatcons =
      match argletpatcons with
      | UTLetPatternCons((argpatrng, _) :: _, _, _) -> argpatrng
      | _                                           -> assert false
    in
    let rec get_last_range argletpatcons =
      match argletpatcons with
      | UTEndOfLetPattern                                             -> assert false
      | UTLetPatternCons(argpatcons, (lastrng, _), UTEndOfLetPattern) -> lastrng
      | UTLetPatternCons(_, _, tailcons)                              -> get_last_range tailcons
    in
      make_range (Rng (get_first_range argletpatcons)) (Rng (get_last_range argletpatcons))


  and make_pattern_match_cons_of_argument_pattern_cons (argletpatcons : untyped_let_pattern_cons) : untyped_pattern_match_cons =
    match argletpatcons with
    | UTEndOfLetPattern                                         -> UTEndOfPatternMatch
    | UTLetPatternCons(argpatcons, utastdef, argletpattailcons) ->
        let tailpmcons = make_pattern_match_cons_of_argument_pattern_cons argletpattailcons in
        let prodpatrng = get_range_of_argument_variable_cons argpatcons in
        let prodpat    = make_product_pattern_of_argument_cons prodpatrng argpatcons in
          UTPatternMatchCons(prodpat, utastdef, tailpmcons)

  and get_range_of_argument_variable_cons (argpatcons : untyped_argument_variable_cons) : Range.t =
    let first_range =
      match argpatcons with
      | (fstrng, _) :: _ -> fstrng
      | _                -> assert false
    in
    let rec get_last_range apcons =
      match apcons with
      | []                  -> assert false
      | (lastrng, _) :: []  -> lastrng
      | _ :: tailargpatcons -> get_last_range tailargpatcons
    in
      make_range (Rng first_range) (Rng (get_last_range argpatcons))


  and make_product_pattern_of_argument_cons (prodpatrng : Range.t) (argpatcons : untyped_argument_variable_cons) : untyped_pattern_tree =
    let rec aux argpatcons =
      match argpatcons with
      | []                 -> (Range.dummy "endofargvar", UTPEndOfTuple)
      | argpat :: tailcons -> (Range.dummy "argvarcons", UTPTupleCons(argpat, aux tailcons))
    in
      let (_, prodpatmain) = aux argpatcons in (prodpatrng, prodpatmain)


  and make_lambda_abstract_for_parallel
      (fullrng : Range.t) (argletpatcons : untyped_let_pattern_cons)
      (pmcons : untyped_pattern_match_cons)
  =
    match argletpatcons with
    | UTEndOfLetPattern                  -> assert false
    | UTLetPatternCons(argpatcons, _, _) ->
        make_lambda_abstract_for_parallel_sub fullrng (fun u -> u) 0 argpatcons pmcons


  and make_lambda_abstract_for_parallel_sub
      (fullrng : Range.t) (k : untyped_abstract_tree -> untyped_abstract_tree)
      (i : int) (argpatcons : untyped_argument_variable_cons)
      (pmcons : untyped_pattern_match_cons)
  : untyped_abstract_tree
  =
    match argpatcons with
    | []                   -> (fullrng, UTPatternMatch(k (Range.dummy "endoftuple", UTEndOfTuple), pmcons))
    | (rng, _) :: tailcons ->
(*        let knew = (fun u -> k (dummy_range, UTTupleCons((rng, UTContentOf(numbered_var_name i)), u))) in *)
(*        let knew = (fun u -> k (dummy_range, UTTupleCons(((3000, 0, 0, 0), UTContentOf(numbered_var_name i)), u))) in (* for test *) *)
        let knew = (fun u -> k (Range.dummy "knew1", UTTupleCons((Range.dummy "knew2", UTContentOf([], numbered_var_name i)), u))) in (* for test *)
        let after = make_lambda_abstract_for_parallel_sub fullrng knew (i + 1) tailcons pmcons in
          (Range.dummy "pattup1", UTLambdaAbstract(Range.dummy "pattup2", numbered_var_name i, after))

  and numbered_var_name i = "%pattup" ^ (string_of_int i)


  let kind_type_argument_cons (uktyargcons : untyped_unkinded_type_argument_cons) (constrntcons : constraint_cons) : untyped_type_argument_cons =
    uktyargcons |> List.map (fun (rng, tyvarnm) ->
      try
        let mkd = List.assoc tyvarnm constrntcons in (rng, tyvarnm, mkd)
      with
      | Not_found -> (rng, tyvarnm, MUniversalKind)
    )


  let make_mutual_variant_cons (uktyargcons : untyped_unkinded_type_argument_cons) (tynmtk : Range.t * type_name) (constrdecs : untyped_variant_cons) (constrntcons : constraint_cons) (tailcons : untyped_mutual_variant_cons) =
    let tynm = extract_name tynmtk in
    let tynmrng = get_range tynmtk in
    let tyargcons = kind_type_argument_cons uktyargcons constrntcons in
      UTMutualVariantCons(tyargcons, tynmrng, tynm, constrdecs, tailcons)

  let make_mutual_synonym_cons (uktyargcons : untyped_unkinded_type_argument_cons) (tynmtk : Range.t * type_name) (mnty : manual_type) (constrntcons : constraint_cons) (tailcons : untyped_mutual_variant_cons) =
    let tynm = extract_name tynmtk in
    let tynmrng = get_range tynmtk in
    let tyargcons = kind_type_argument_cons uktyargcons constrntcons in
      UTMutualSynonymCons(tyargcons, tynmrng, tynm, mnty, tailcons)

  let make_module
      (firsttk : Range.t) (mdlnmtk : Range.t * module_name) (msigopt : (manual_signature_content list) option)
      (utastdef : untyped_abstract_tree) (utastaft : untyped_abstract_tree)
  : untyped_abstract_tree
  =
    let mdlrng = make_range (Tok firsttk) (Untyped utastdef) in
    let mdlnm = extract_name mdlnmtk in
      make_standard (Tok firsttk) (Untyped utastaft) (UTModule(mdlrng, mdlnm, msigopt, utastdef, utastaft))


  let rec make_list_to_itemize (lst : (Range.t * int * untyped_abstract_tree) list) =
    (Range.dummy "itemize1", UTItemize(make_list_to_itemize_sub (UTItem((Range.dummy "itemize2", UTStringEmpty), [])) lst 0))

  and make_list_to_itemize_sub (resitmz : untyped_itemize) (lst : (Range.t * int * untyped_abstract_tree) list) (crrntdp : int) =
    match lst with
    | []                          -> resitmz
    | (rng, depth, utast) :: tail ->
        if depth <= crrntdp + 1 then
          let newresitmz = insert_last [] resitmz 1 depth utast in
            make_list_to_itemize_sub newresitmz tail depth
        else
          raise (ParseErrorDetail("syntax error: illegal item depth "
            ^ (string_of_int depth) ^ " after " ^ (string_of_int crrntdp) ^ "\n"
            ^ "    " ^ (Range.to_string rng)))

  and insert_last (resitmzlst : untyped_itemize list) (itmz : untyped_itemize) (i : int) (depth : int) (utast : untyped_abstract_tree) : untyped_itemize =
    match itmz with
    | UTItem(uta, []) ->
        if i < depth then assert false else UTItem(uta, [UTItem(utast, [])])
    | UTItem(uta, hditmz :: []) ->
        if i < depth then
          UTItem(uta, resitmzlst @ [insert_last [] hditmz (i + 1) depth utast])
        else
          UTItem(uta, resitmzlst @ [hditmz] @ [UTItem(utast, [])])
    | UTItem(uta, hditmz :: tlitmzlst) ->
        insert_last (resitmzlst @ [hditmz]) (UTItem(uta, tlitmzlst)) i depth utast

  (* range_kind -> string -> 'a *)
  let report_error (rngknd : range_kind) (tok : string) =
    match rngknd with
    | Tok(rng) ->
          raise (ParseErrorDetail(
            "syntax error:\n"
            ^ "    unexpected token after '" ^ tok ^ "'\n"
            ^ "    " ^ (Range.to_string rng)))
    | TokArg(rng, nm) ->
          raise (ParseErrorDetail(
            "syntax error:\n"
            ^ "    unexpected token after '" ^ nm ^ "'\n"
            ^ "    " ^ (Range.to_string rng)))
    | _ -> assert false

%}

%token <Range.t * Types.var_name> VAR
%token <Range.t * (Types.module_name list) * Types.var_name> VARWITHMOD
%token <Range.t * (Types.module_name list) * Types.ctrlseq_name> CTRLSEQWITHMOD
%token <Range.t * Types.var_name> VARINSTR
%token <Range.t * Types.var_name> TYPEVAR
%token <Range.t * Types.constructor_name> CONSTRUCTOR
%token <Range.t * string> NUMCONST CHAR
%token <Range.t * Types.ctrlseq_name> CTRLSEQ
%token <Range.t * Types.id_name>      IDNAME
%token <Range.t * Types.class_name>   CLASSNAME
%token <Range.t> SPACE BREAK
%token <Range.t> LAMBDA ARROW
%token <Range.t> LET DEFEQ LETAND IN
%token <Range.t> MODULE STRUCT END DIRECT DOT SIG VAL CONSTRAINT
%token <Range.t> TYPE OF MATCH WITH BAR WILDCARD WHEN AS COLON
%token <Range.t> LETMUTABLE OVERWRITEEQ LETLAZY
%token <Range.t> REFNOW REFFINAL
%token <Range.t> IF THEN ELSE
%token <Range.t> TIMES DIVIDES MOD PLUS MINUS EQ NEQ GEQ LEQ GT LT LNOT LAND LOR CONCAT
%token <Range.t> LPAREN RPAREN
%token <Range.t> BGRP EGRP
%token <Range.t> OPENQT CLOSEQT
%token <Range.t> OPENSTR CLOSESTR
%token <Range.t> OPENNUM CLOSENUM
%token <Range.t> TRUE FALSE
%token <Range.t> SEP ENDACTIVE COMMA
%token <Range.t> BLIST LISTPUNCT ELIST CONS BRECORD ERECORD ACCESS CONSTRAINEDBY
%token <Range.t> OPENNUM_AND_BRECORD CLOSENUM_AND_ERECORD OPENNUM_AND_BLIST CLOSENUM_AND_ELIST
%token <Range.t> BEFORE UNITVALUE WHILE DO
%token <Range.t> NEWGLOBALHASH OVERWRITEGLOBALHASH RENEWGLOBALHASH
%token <Range.t * int> ITEM
%token EOI
%token IGNORED

%nonassoc LET DEFEQ IN LETAND LETMUTABLE OVERWRITEEQ
%nonassoc MATCH WITH
%nonassoc IF THEN ELSE
%left OVERWRITEGLOBALHASH
%left BEFORE
%nonassoc WHILE
%left LOR
%left LAND
%nonassoc LNOT
%left EQ NEQ
%left GEQ LEQ GT LT
%right CONS
%left PLUS
%left MINUS
%left TIMES
%right MOD DIVIDES
%nonassoc VAR
%nonassoc LPAREN RPAREN

%start main
%type <Types.untyped_abstract_tree> main
%type <Types.untyped_abstract_tree> nxlet
%type <Types.untyped_abstract_tree> nxletsub
%type <Types.untyped_mutual_let_cons> nxdec
%type <Types.untyped_abstract_tree> nxbfr
%type <Types.untyped_abstract_tree> nxwhl
%type <Types.untyped_abstract_tree> nxif
%type <Types.untyped_abstract_tree> nxlor
%type <Types.untyped_abstract_tree> nxland
%type <Types.untyped_abstract_tree> nxcomp
%type <Types.untyped_abstract_tree> nxconcat
%type <Types.untyped_abstract_tree> nxlplus
%type <Types.untyped_abstract_tree> nxltimes
%type <Types.untyped_abstract_tree> nxrplus
%type <Types.untyped_abstract_tree> nxrtimes
%type <Types.untyped_abstract_tree> nxun
%type <Types.untyped_abstract_tree> nxapp
%type <Types.untyped_abstract_tree> nxbot
%type <Types.untyped_abstract_tree> tuple
%type <Range.t * Types.untyped_pattern_match_cons> pats
%type <Types.untyped_pattern_tree> patas
%type <Types.untyped_pattern_tree> patbot
%type <Types.untyped_abstract_tree> nxlist
%type <Types.untyped_abstract_tree> sxsep
%type <Types.untyped_abstract_tree> sxsepsub
%type <Types.untyped_abstract_tree> sxblock
%type <Types.untyped_abstract_tree> sxbot
%type <Types.untyped_abstract_tree> sxclsnm
%type <Types.untyped_abstract_tree> sxidnm
%type <Types.untyped_argument_cons> narg
%type <Types.untyped_argument_cons> sarg
%type <Types.untyped_argument_cons> sargsub
%type <Types.untyped_argument_variable_cons> argvar
%type <string> binop
%type <Types.untyped_unkinded_type_argument_cons> xpltyvars

%%


main:
  | nxtoplevel  { $1 }
  | sxblock EOI { $1 }
;
nxtoplevel:
/* ---- toplevel style ---- */
  | LET nxdec nxtoplevel                                           { make_let_expression $1 $2 $3 }
  | LET nxdec EOI                                                  { make_let_expression $1 $2 end_header }
  | LETMUTABLE VAR OVERWRITEEQ nxlet nxtoplevel                    { make_let_mutable_expression $1 $2 $4 $5 }
  | LETMUTABLE VAR OVERWRITEEQ nxlet EOI                           { make_let_mutable_expression $1 $2 $4 end_header }
  | TYPE nxvariantdec nxtoplevel                                   { make_variant_declaration $1 $2 $3 }
  | TYPE nxvariantdec EOI                                          { make_variant_declaration $1 $2 end_header }
  | LETLAZY nxlazydec nxtoplevel                                   { make_let_expression $1 $2 $3 }
  | LETLAZY nxlazydec EOI                                          { make_let_expression $1 $2 end_header }
  | MODULE CONSTRUCTOR nxsigopt DEFEQ STRUCT nxstruct nxtoplevel   { make_module $1 $2 $3 $6 $7 }
  | MODULE CONSTRUCTOR nxsigopt DEFEQ STRUCT nxstruct EOI          { make_module $1 $2 $3 $6 end_header }
/* ---- transition to expression style ---- */
  | LET nxdec IN nxlet EOI                                         { make_let_expression $1 $2 $4 }
  | LETMUTABLE VAR OVERWRITEEQ nxlet IN nxlet EOI                  { make_let_mutable_expression $1 $2 $4 $6 }
  | TYPE nxvariantdec IN nxlet EOI                                 { make_variant_declaration $1 $2 $4 }
  | LETLAZY nxlazydec IN nxlet EOI                                 { make_let_expression $1 $2 $4 }
  | MODULE CONSTRUCTOR nxsigopt DEFEQ STRUCT nxstruct IN nxlet EOI { make_module $1 $2 $3 $6 $8 }
/* ---- for syntax error log -- */
  | LET error                                      { report_error (Tok $1) "let" }
  | LET nxdec IN error                             { report_error (Tok $3) "in" }
  | LETMUTABLE error                               { report_error (Tok $1) "let-mutable"}
  | LETMUTABLE VAR error                           { report_error (TokArg $2) "" }
  | LETMUTABLE VAR OVERWRITEEQ error               { report_error (Tok $3) "<-" }
  | LETMUTABLE VAR OVERWRITEEQ nxlet IN error      { report_error (Tok $5) "in" }
  | TYPE error                                     { report_error (Tok $1) "variant" }
  | MODULE error                                   { report_error (Tok $1) "module" }
  | MODULE CONSTRUCTOR nxsigopt DEFEQ error        { report_error (Tok $4) "=" }
  | MODULE CONSTRUCTOR nxsigopt DEFEQ STRUCT error { report_error (Tok $5) "struct" }
;
nxsigopt:
  |                 { None }
  | COLON SIG nxsig { Some($3) }
;
nxsig:
  | END                                        { [] }
  | TYPE xpltyvars VAR constrnt nxsig          { let (_, tynm) = $3 in (SigType(kind_type_argument_cons $2 $4, tynm)) :: $5 }
  | VAL VAR COLON txfunc constrnt nxsig        { let (_, varnm) = $2 in (SigValue(varnm, $4, $5)) :: $6 }
  | VAL CTRLSEQ COLON txfunc constrnt nxsig    { let (_, csnm) = $2 in (SigValue(csnm, $4, $5)) :: $6 }
  | DIRECT CTRLSEQ COLON txfunc constrnt nxsig { let (_, csnm) = $2 in (SigDirect(csnm, $4, $5)) :: $6 }
/* ---- for syntax error log -- */
  | TYPE error                 { report_error (Tok $1) "type" }
  | TYPE xpltyvars VAR error   { report_error (TokArg $3) "" }
  | VAL error                  { report_error (Tok $1) "val" }
  | VAL VAR error              { report_error (TokArg $2) "" }
  | VAL VAR COLON error        { report_error (Tok $3) ":" }
  | VAL CTRLSEQ error          { report_error (TokArg $2) "" }
  | VAL CTRLSEQ COLON error    { report_error (Tok $3) ":" }
  | DIRECT error               { report_error (Tok $1) "direct" }
  | DIRECT CTRLSEQ error       { report_error (TokArg $2) "" }
  | DIRECT CTRLSEQ COLON error { report_error (Tok $3) ":" }
;
constrnt:
  |                                        { [] }
  | CONSTRAINT TYPEVAR CONS kxtop constrnt { let (_, tyvarnm) = $2 in (tyvarnm, $4) :: $5 }
;
nxstruct:
/* ---- toplevel style ---- */
  | END                                                            { (end_struct $1) }
  | LET nxdec nxstruct                                             { make_let_expression $1 $2 $3 }
  | LETMUTABLE VAR OVERWRITEEQ nxlet nxstruct                      { make_let_mutable_expression $1 $2 $4 $5 }
  | TYPE nxvariantdec nxstruct                                     { make_variant_declaration $1 $2 $3 }
  | LETLAZY nxlazydec nxstruct                                     { make_let_expression $1 $2 $3 }
  | MODULE CONSTRUCTOR nxsigopt DEFEQ STRUCT nxstruct nxstruct     { make_module $1 $2 $3 $6 $7 }
;
nxdec: /* -> untyped_mutual_let_cons */
  | VAR COLON txfunc DEFEQ nxlet LETAND nxdec            { make_mutual_let_cons (Some $3) $1 end_of_argument_variable $5 $7 }

  | VAR COLON txfunc DEFEQ nxlet                         { make_mutual_let_cons (Some $3) $1 end_of_argument_variable $5 end_of_mutual_let }

  | VAR     argvar DEFEQ nxlet LETAND nxdec              { make_mutual_let_cons None $1 $2 $4 $6 }
  | VAR COLON txfunc BAR
            argvar DEFEQ nxlet LETAND nxdec              { make_mutual_let_cons (Some $3) $1 $5 $7 $9 }

  | VAR     argvar DEFEQ nxlet                           { make_mutual_let_cons None $1 $2 $4 end_of_mutual_let }
  | VAR COLON txfunc BAR
            argvar DEFEQ nxlet                           { make_mutual_let_cons (Some $3) $1 $5 $7 end_of_mutual_let }

  | VAR     argvar DEFEQ nxlet BAR nxdecpar LETAND nxdec { make_mutual_let_cons_par None $1 (UTLetPatternCons($2, $4, $6)) $8 }
  | VAR BAR argvar DEFEQ nxlet BAR nxdecpar LETAND nxdec { make_mutual_let_cons_par None $1 (UTLetPatternCons($3, $5, $7)) $9 }
  | VAR COLON txfunc BAR
            argvar DEFEQ nxlet BAR nxdecpar LETAND nxdec { make_mutual_let_cons_par (Some $3) $1 (UTLetPatternCons($5, $7, $9)) $11 }

  | VAR     argvar DEFEQ nxlet BAR nxdecpar              { make_mutual_let_cons_par None $1 (UTLetPatternCons($2, $4, $6)) end_of_mutual_let }
  | VAR BAR argvar DEFEQ nxlet BAR nxdecpar              { make_mutual_let_cons_par None $1 (UTLetPatternCons($3, $5, $7)) end_of_mutual_let }
  | VAR COLON txfunc BAR
            argvar DEFEQ nxlet BAR nxdecpar              { make_mutual_let_cons_par (Some $3) $1 (UTLetPatternCons($5, $7, $9)) end_of_mutual_let }

  | CTRLSEQ COLON txfunc DEFEQ nxlet LETAND nxdec        { make_mutual_let_cons (Some $3) $1 end_of_argument_variable (class_and_id_region $5) $7 }

  | CTRLSEQ COLON txfunc DEFEQ nxlet                     { make_mutual_let_cons (Some $3) $1 end_of_argument_variable (class_and_id_region $5) end_of_mutual_let }

  | CTRLSEQ     argvar DEFEQ nxlet LETAND nxdec              { make_mutual_let_cons None $1 $2 (class_and_id_region $4) $6 }
  | CTRLSEQ COLON txfunc BAR
                argvar DEFEQ nxlet LETAND nxdec              { make_mutual_let_cons (Some $3) $1 $5 (class_and_id_region $7) $9 }

  | CTRLSEQ     argvar DEFEQ nxlet                           { make_mutual_let_cons None $1 $2 (class_and_id_region $4) end_of_mutual_let }
  | CTRLSEQ COLON txfunc BAR
                argvar DEFEQ nxlet                           { make_mutual_let_cons (Some $3) $1 $5 (class_and_id_region $7) end_of_mutual_let }

  | CTRLSEQ     argvar DEFEQ nxlet BAR nxdecpar LETAND nxdec { make_mutual_let_cons_par None $1 (UTLetPatternCons($2, class_and_id_region $4, $6)) $8 }
  | CTRLSEQ BAR argvar DEFEQ nxlet BAR nxdecpar LETAND nxdec { make_mutual_let_cons_par None $1 (UTLetPatternCons($3, class_and_id_region $5, $7)) $9 }
  | CTRLSEQ COLON txfunc BAR
                argvar DEFEQ nxlet BAR nxdecpar LETAND nxdec { make_mutual_let_cons_par (Some $3) $1 (UTLetPatternCons($5, class_and_id_region $7, $9)) $11 }

  | CTRLSEQ     argvar DEFEQ nxlet BAR nxdecpar              { make_mutual_let_cons_par None $1 (UTLetPatternCons($2, class_and_id_region $4, $6)) end_of_mutual_let }
  | CTRLSEQ BAR argvar DEFEQ nxlet BAR nxdecpar              { make_mutual_let_cons_par None $1 (UTLetPatternCons($3, class_and_id_region $5, $7)) end_of_mutual_let }
  | CTRLSEQ COLON txfunc BAR
                argvar DEFEQ nxlet BAR nxdecpar              { make_mutual_let_cons_par (Some $3) $1 (UTLetPatternCons($5, class_and_id_region $7, $9)) end_of_mutual_let }
/* -- for syntax error log -- */
  | VAR error                                        { report_error (TokArg $1) "" }
  | VAR COLON error                                  { report_error (Tok $2) ":" }
  | VAR COLON txfunc DEFEQ error                     { report_error (Tok $4) "=" }
  | VAR COLON txfunc BAR
        error                                        { report_error (Tok $4) "|" }
  | VAR COLON txfunc BAR
        argvar DEFEQ error                           { report_error (Tok $6) "=" }
  | VAR COLON txfunc BAR
        argvar DEFEQ nxlet BAR error                 { report_error (Tok $8) "|" }
  | VAR COLON txfunc BAR
        argvar DEFEQ nxlet LETAND error              { report_error (Tok $8) "and" }
  | VAR COLON txfunc BAR
        argvar DEFEQ nxlet BAR nxdecpar LETAND error { report_error (Tok $10) "and" }
  | VAR argvar DEFEQ error                           { report_error (Tok $3) "=" }
  | VAR argvar DEFEQ nxlet BAR error                 { report_error (Tok $5) "|" }
  | VAR argvar DEFEQ nxlet LETAND error              { report_error (Tok $5) "and" }
  | VAR argvar DEFEQ nxlet BAR nxdecpar LETAND error { report_error (Tok $7) "and" }
  | CTRLSEQ error                                    { report_error (TokArg $1) "" }
  | CTRLSEQ argvar DEFEQ error                       { report_error (Tok $3) "=" }
  | CTRLSEQ argvar DEFEQ nxlet BAR error             { report_error (Tok $5) "|" }
  | CTRLSEQ argvar DEFEQ nxlet LETAND error          { report_error (Tok $5) "and" }
/* -- -- */
;
nxdecpar:
  | argvar DEFEQ nxlet BAR nxdecpar { UTLetPatternCons($1, $3, $5) }
  | argvar DEFEQ nxlet              { UTLetPatternCons($1, $3, UTEndOfLetPattern) }
/* -- for syntax error log -- */
  | argvar DEFEQ error           { report_error (Tok $2) "=" }
  | argvar DEFEQ nxlet BAR error { report_error (Tok $4) "|" }
/* -- -- */
;
nxlazydec:
  | VAR DEFEQ nxlet LETAND nxlazydec {
        let rng = make_range (Untyped $3) (Untyped $3) in
          make_mutual_let_cons None $1 end_of_argument_variable (rng, UTLazyContent($3)) $5
      }
  | VAR COLON txfunc DEFEQ nxlet LETAND nxlazydec {
        let rng = make_range (Untyped $5) (Untyped $5) in
          make_mutual_let_cons (Some $3) $1 end_of_argument_variable (rng, UTLazyContent($5)) $7
      }
  | VAR DEFEQ nxlet {
        let rng = make_range (Untyped $3) (Untyped $3) in
          make_mutual_let_cons None $1 end_of_argument_variable (rng, UTLazyContent($3)) end_of_mutual_let
      }
  | VAR COLON txfunc DEFEQ nxlet {
        let rng = make_range (Untyped $5) (Untyped $5) in
          make_mutual_let_cons (Some $3) $1 end_of_argument_variable (rng, UTLazyContent($5)) end_of_mutual_let
      }
  | CTRLSEQ DEFEQ nxlet LETAND nxlazydec {
        let rng = make_range (Untyped $3) (Untyped $3) in
          make_mutual_let_cons None $1 end_of_argument_variable (rng, UTLazyContent(class_and_id_region $3)) $5
      }
  | CTRLSEQ COLON txfunc DEFEQ nxlet LETAND nxlazydec {
        let rng = make_range (Untyped $5) (Untyped $5) in
          make_mutual_let_cons (Some $3) $1 end_of_argument_variable (rng, UTLazyContent(class_and_id_region $5)) $7
      }
  | CTRLSEQ DEFEQ nxlet {
        let rng = make_range (Untyped $3) (Untyped $3) in
          make_mutual_let_cons None $1 end_of_argument_variable (rng, UTLazyContent(class_and_id_region $3)) end_of_mutual_let
      }
  | CTRLSEQ COLON txfunc DEFEQ nxlet {
        let rng = make_range (Untyped $5) (Untyped $5) in
          make_mutual_let_cons (Some $3) $1 end_of_argument_variable (rng, UTLazyContent(class_and_id_region $5)) end_of_mutual_let
      }
/* -- for syntax error log -- */
  | VAR error                                 { report_error (TokArg $1) "" }
  | VAR COLON error                           { report_error (Tok $2) ":" }
  | VAR COLON txfunc DEFEQ error              { report_error (Tok $4) "=" }
  | VAR COLON txfunc DEFEQ nxlet LETAND error { report_error (Tok $6) "and" }
  | VAR DEFEQ error                           { report_error (Tok $2) "=" }
  | VAR DEFEQ nxlet LETAND error              { report_error (Tok $4) "and" }
/* -- -- */
;
nxvariantdec: /* -> untyped_mutual_variant_cons */
  | xpltyvars VAR DEFEQ variants constrnt LETAND nxvariantdec     { make_mutual_variant_cons $1 $2 $4 $5 $7 }
  | xpltyvars VAR DEFEQ variants constrnt                         { make_mutual_variant_cons $1 $2 $4 $5 UTEndOfMutualVariant }
  | xpltyvars VAR DEFEQ BAR variants constrnt LETAND nxvariantdec { make_mutual_variant_cons $1 $2 $5 $6 $8 }
  | xpltyvars VAR DEFEQ BAR variants constrnt                     { make_mutual_variant_cons $1 $2 $5 $6 UTEndOfMutualVariant }
  | xpltyvars VAR DEFEQ txfunc constrnt LETAND nxvariantdec       { make_mutual_synonym_cons $1 $2 $4 $5 $7 }
  | xpltyvars VAR DEFEQ txfunc constrnt                           { make_mutual_synonym_cons $1 $2 $4 $5 UTEndOfMutualVariant }
/* -- for syntax error log -- */
  | xpltyvars VAR error                           { report_error (TokArg $2) "" }
  | xpltyvars VAR DEFEQ error                     { report_error (Tok $3) "=" }
  | xpltyvars VAR DEFEQ BAR error                 { report_error (Tok $4) "|" }
  | xpltyvars VAR DEFEQ BAR variants LETAND error { report_error (Tok $6) "and" }
/* -- -- */
;
xpltyvars:
  | TYPEVAR xpltyvars                          { let (rng, tyargnm) = $1 in (rng, tyargnm) :: $2 }
/*
  | LPAREN TYPEVAR CONS kxtop RPAREN xpltyvars { let (rng, tyargnm) = $2 in (rng, tyargnm, $4) :: $6 }
*/
  |                                            { [] }
;
kxtop:
  | BRECORD txrecord ERECORD { MRecordKind(Assoc.of_list $2) }
;
nxlet:
  | MATCH nxlet WITH pats      {
        let (lastrng, pmcons) = $4 in make_standard (Tok $1) (Rng lastrng) (UTPatternMatch($2, pmcons)) }
  | MATCH nxlet WITH BAR pats  {
        let (lastrng, pmcons) = $5 in make_standard (Tok $1) (Rng lastrng) (UTPatternMatch($2, pmcons)) }
  | nxletsub                   { $1 }
/* -- for syntax error log -- */
  | MATCH error                { report_error (Tok $1) "match" }
  | MATCH nxlet WITH error     { report_error (Tok $3) "with" }
  | MATCH nxlet WITH BAR error { report_error (Tok $4) "|" }
/* -- -- */
nxletsub:
  | LET nxdec IN nxlet                        { make_let_expression $1 $2 $4 }
  | LET patbotwithoutvar DEFEQ nxlet IN nxlet { make_standard (Tok $1) (Untyped $6)
                                                  (UTPatternMatch($4, UTPatternMatchCons($2, $6, UTEndOfPatternMatch))) }
  | LETMUTABLE VAR OVERWRITEEQ nxlet IN nxlet { make_let_mutable_expression $1 $2 $4 $6 }
  | nxwhl { $1 }
/* -- for syntax error log -- */
  | LET error                                 { report_error (Tok $1) "let" }
  | LETMUTABLE error                          { report_error (Tok $1) "let-mutable" }
  | LETMUTABLE VAR error                      { report_error (TokArg $2) "" }
  | LETMUTABLE VAR OVERWRITEEQ error          { report_error (Tok $3) "->" }
  | LETMUTABLE VAR OVERWRITEEQ nxlet IN error { report_error (Tok $5) "in" }
/* -- -- */
;
nxwhl:
  | WHILE nxlet DO nxwhl { make_standard (Tok $1) (Untyped $4) (UTWhileDo($2, $4)) }
  | nxif                 { $1 }
/* -- for syntax error log -- */
  | WHILE error          { report_error (Tok $1) "while" }
  | WHILE nxlet DO error { report_error (Tok $3) "do" }
/* -- -- */
nxif:
  | IF nxlet THEN nxlet ELSE nxlet       { make_standard (Tok $1) (Untyped $6) (UTIfThenElse($2, $4, $6)) }
  | nxbfr                                { $1 }
/* -- for syntax error log -- */
  | IF error                             { report_error (Tok $1) "if" }
  | IF nxlet THEN error                  { report_error (Tok $3) "then" }
  | IF nxlet THEN nxlet ELSE error       { report_error (Tok $5) "else" }
/* -- -- */
;
nxbfr:
  | nxlambda BEFORE nxbfr { make_standard (Untyped $1) (Untyped $3) (UTSequential($1, $3)) }
  | nxlambda              { $1 }
/* -- for syntax error log -- */
  | nxlambda BEFORE error { report_error (Tok $2) "before" }
/* -- -- */
;
nxlambda:
  | VAR OVERWRITEEQ nxlor {
        let (varrng, varnm) = $1 in
          make_standard (TokArg $1) (Untyped $3) (UTOverwrite(varrng, varnm, $3)) }
  | NEWGLOBALHASH nxlet OVERWRITEGLOBALHASH nxlor {
        make_standard (Tok $1) (Untyped $4) (UTDeclareGlobalHash($2, $4)) }
  | RENEWGLOBALHASH nxlet OVERWRITEGLOBALHASH nxlor {
        make_standard (Tok $1) (Untyped $4) (UTOverwriteGlobalHash($2, $4)) }
  | LAMBDA argvar ARROW nxlor {
        let rng = make_range (Tok $1) (Untyped $4) in curry_lambda_abstract rng $2 $4 }
  | nxlor { $1 }
/* -- for syntax error log -- */
  | VAR error                                       { report_error (TokArg $1) "" }
  | NEWGLOBALHASH error                             { report_error (Tok $1) "new-global-hash" }
  | NEWGLOBALHASH nxlet OVERWRITEGLOBALHASH error   { report_error (Tok $3) "<<-" }
  | RENEWGLOBALHASH error                           { report_error (Tok $1) "renew-global-hash" }
  | RENEWGLOBALHASH nxlet OVERWRITEGLOBALHASH error { report_error (Tok $3) "<<-" }
  | LAMBDA error                                    { report_error (Tok $1) "function" }
  | LAMBDA argvar ARROW error                       { report_error (Tok $3) "->" }
/* -- -- */
;
argvar: /* -> argument_variable_cons */
  | patbot argvar                           { $1 :: $2 }
/*
  | patbot argvar                           { UTArgumentVariableCons($1, NoTypeAnnotationForArgument, $2) }
  | LPAREN patas RPAREN argvar              { UTArgumentVariableCons($2, NoTypeAnnotationForArgument, $4) }
  | LPAREN patas COLON txfunc RPAREN argvar { UTArgumentVariableCons($2, TypeAnnotationForArgument($4), $6) }
*/
  |                                         { end_of_argument_variable }
;
nxlor:
  | nxland LOR nxlor    { binary_operator "||" $1 $2 $3 }
  | nxland              { $1 }
/* -- for syntax error log -- */
  | nxland LOR error    { report_error (Tok $2) "||" }
/* -- -- */
;
nxland:
  | nxcomp LAND nxland  { binary_operator "&&" $1 $2 $3 }
  | nxcomp              { $1 }
/* -- for syntax error log -- */
  | nxcomp LAND error   { report_error (Tok $2) "&&" }
/* -- -- */
;
nxcomp:
  | nxconcat EQ nxcomp  { binary_operator "==" $1 $2 $3 }
  | nxconcat NEQ nxcomp { binary_operator "<>" $1 $2 $3 }
  | nxconcat GEQ nxcomp { binary_operator ">=" $1 $2 $3 }
  | nxconcat LEQ nxcomp { binary_operator "<=" $1 $2 $3 }
  | nxconcat GT nxcomp  { binary_operator ">" $1 $2 $3 }
  | nxconcat LT nxcomp  { binary_operator "<" $1 $2 $3 }
  | nxconcat            { $1 }
/* -- for syntax error log -- */
  | nxconcat EQ error   { report_error (Tok $2) "==" }
  | nxconcat NEQ error  { report_error (Tok $2) "<>" }
  | nxconcat GEQ error  { report_error (Tok $2) ">=" }
  | nxconcat LEQ error  { report_error (Tok $2) "<=" }
  | nxconcat GT error   { report_error (Tok $2) ">" }
  | nxconcat LT error   { report_error (Tok $2) "<" }
/* -- -- */
;
nxconcat:
  | nxlplus CONCAT nxconcat { binary_operator "^" $1 $2 $3 }
  | nxlplus CONS nxconcat   { binary_operator "::" $1 $2 $3 }
  | nxlplus                 { $1 }
/* -- for syntax error log -- */
  | nxlplus CONCAT error    { report_error (Tok $2) "^" }
/* -- -- */
;
nxlplus:
  | nxlminus PLUS nxrplus   { binary_operator "+" $1 $2 $3 }
  | nxlminus                { $1 }
/* -- for syntax error log -- */
  | nxlminus PLUS error     { report_error (Tok $2) "+" }
/* -- -- */
;
nxlminus:
  | nxlplus MINUS nxrtimes  { binary_operator "-" $1 $2 $3 }
  | nxltimes                { $1 }
/* -- for syntax error log -- */
  | nxlplus MINUS error     { report_error (Tok $2) "-" }
/* -- -- */
;
nxrplus:
  | nxrminus PLUS nxrplus   { binary_operator "+" $1 $2 $3 }
  | nxrminus                { $1 }
/* -- for syntax error log -- */
  | nxrminus PLUS error     { report_error (Tok $2) "+" }
/* -- -- */
;
nxrminus:
  | nxrplus MINUS nxrtimes  { binary_operator "-" $1 $2 $3 }
  | nxrtimes                { $1 }
/* -- for syntax error log -- */
  | nxrplus MINUS error     { report_error (Tok $2) "-" }
/* -- -- */
;
nxltimes:
  | nxun TIMES nxrtimes     { binary_operator "*" $1 $2 $3 }
  | nxltimes DIVIDES nxapp  { binary_operator "/" $1 $2 $3 }
  | nxltimes MOD nxapp      { binary_operator "mod" $1 $2 $3 }
  | nxun                    { $1 }
/* -- for syntax error log -- */
  | nxun TIMES error        { report_error (Tok $2) "*" }
  | nxltimes DIVIDES error  { report_error (Tok $2) "/" }
  | nxltimes MOD error      { report_error (Tok $2) "mod" }
/* -- -- */
;
nxrtimes:
  | nxapp TIMES nxrtimes   { binary_operator "*" $1 $2 $3 }
  | nxrtimes DIVIDES nxapp { binary_operator "/" $1 $2 $3 }
  | nxrtimes MOD nxapp     { binary_operator "mod" $1 $2 $3 }
  | nxapp                  { $1 }
/* -- for syntax error log -- */
  | nxapp TIMES error      { report_error (Tok $2) "*" }
  | nxrtimes DIVIDES error { report_error (Tok $2) "/" }
  | nxrtimes MOD error     { report_error (Tok $2) "mod" }
/* -- -- */
;
nxun:
  | MINUS nxapp       { binary_operator "-" (Range.dummy "zero-of-unary-minus", UTNumericConstant(0)) $1 $2 }
  | LNOT nxapp        { make_standard (Tok $1) (Untyped $2) (UTApply(($1, UTContentOf([], "not")), $2)) }
  | CONSTRUCTOR nxbot { make_standard (TokArg $1) (Untyped $2) (UTConstructor(extract_name $1, $2)) }
  | CONSTRUCTOR       { make_standard (TokArg $1) (TokArg $1)
                          (UTConstructor(extract_name $1, (Range.dummy "constructor-unitvalue", UTUnitConstant))) }
  | nxapp             { $1 }
/* -- for syntax error log -- */
  | MINUS error       { report_error (Tok $1) "-" }
  | LNOT error        { report_error (Tok $1) "not" }
/* -- -- */
;
nxapp:
  | nxapp nxbot    { make_standard (Untyped $1) (Untyped $2) (UTApply($1, $2)) }
  | REFNOW nxbot   { make_standard (Tok $1) (Untyped $2) (UTApply(($1, UTContentOf([], "!")), $2)) }
  | REFFINAL nxbot { make_standard (Tok $1) (Untyped $2) (UTReferenceFinal($2)) }
  | nxbot          { $1 }
/* -- for syntax error log -- */
  | REFNOW error   { report_error (Tok $1) "!" }
  | REFFINAL error { report_error (Tok $1) "!!" }
/* -- -- */
;
nxbot:
  | nxbot ACCESS VAR                { make_standard (Untyped $1) (TokArg $3) (UTAccessField($1, extract_name $3)) }
  | VAR                             { let (rng, varnm) = $1 in (rng, UTContentOf([], varnm)) }
  | VARWITHMOD                      { let (rng, mdlnmlst, varnm) = $1 in (rng, UTContentOf(mdlnmlst, varnm)) }
  | NUMCONST                        { make_standard (TokArg $1) (TokArg $1)  (UTNumericConstant(int_of_string (extract_name $1))) }
  | TRUE                            { make_standard (Tok $1) (Tok $1) (UTBooleanConstant(true)) }
  | FALSE                           { make_standard (Tok $1) (Tok $1) (UTBooleanConstant(false)) }
  | UNITVALUE                       { make_standard (Tok $1) (Tok $1) UTUnitConstant }
  | LPAREN nxlet RPAREN             { make_standard (Tok $1) (Tok $3) (extract_main $2) }
  | LPAREN nxlet COMMA tuple RPAREN { make_standard (Tok $1) (Tok $5) (UTTupleCons($2, $4)) }
  | OPENSTR sxsep CLOSESTR          { make_standard (Tok $1) (Tok $3) (extract_main $2) }
  | OPENQT sxblock CLOSEQT          { make_standard (Tok $1) (Tok $3) (omit_spaces $2) }
  | BLIST ELIST                     { make_standard (Tok $1) (Tok $2) UTEndOfList }
  | BLIST nxlist ELIST              { make_standard (Tok $1) (Tok $3) (extract_main $2) }
  | LPAREN binop RPAREN             { make_standard (Tok $1) (Tok $3) (UTContentOf([], $2)) }
  | BRECORD ERECORD                 { make_standard (Tok $1) (Tok $2) (UTRecord([])) }
  | BRECORD nxrecord ERECORD        { make_standard (Tok $1) (Tok $3) (UTRecord($2)) }
/* -- for syntax error log -- */
  | BLIST error   { report_error (Tok $1) "[" }
  | OPENSTR error { report_error (Tok $1) "{ (beginning of text area)" }
  | LPAREN error  { report_error (Tok $1) "(" }
  | BRECORD error { report_error (Tok $1) "(|" }
/* -- -- */
;
/*
modulevar:
  | VAR                       { (get_range $1, [], $1) }
  | CONSTRUCTOR DOT modulevar { let (_, mdlnmlst, vartok) = $3 in (get_range $1, (extract_name $1) :: mdlnmlst, vartok) }
;
*/
nxrecord:
  | VAR DEFEQ nxlet                    { (extract_name $1, $3) :: [] }
  | VAR DEFEQ nxlet LISTPUNCT          { (extract_name $1, $3) :: [] }
  | VAR DEFEQ nxlet LISTPUNCT nxrecord { (extract_name $1, $3) :: $5 }
/* -- for syntax error log -- */
  | VAR DEFEQ error { report_error (TokArg $1) ((extract_name $1) ^ " =") }
/* -- -- */
;
nxlist:
  | nxlet LISTPUNCT nxlist { make_standard (Untyped $1) (Untyped $3) (UTListCons($1, $3)) }
  | nxlet LISTPUNCT        { make_standard (Untyped $1) (Tok $2) (UTListCons($1, (Range.dummy "end-of-list", UTEndOfList))) }
  | nxlet                  { make_standard (Untyped $1) (Untyped $1) (UTListCons($1, (Range.dummy "end-of-list", UTEndOfList))) }
/* -- for syntax error log -- */
  | nxlet LISTPUNCT error  { report_error (Tok $2) ";" }
/* -- -- */
;
variants: /* -> untyped_variant_cons */
  | CONSTRUCTOR OF txfunc BAR variants  { make_standard (TokArg $1) (VarntCons $5)
                                            (UTVariantCons(extract_name $1, $3, $5)) }
  | CONSTRUCTOR OF txfunc               { make_standard (TokArg $1) (ManuType $3)
                                            (UTVariantCons(extract_name $1, $3, (Range.dummy "end-of-variant1", UTEndOfVariant))) }
  | CONSTRUCTOR BAR variants            { make_standard (TokArg $1) (VarntCons $3)
                                             (UTVariantCons(extract_name $1, (Range.dummy "dec-constructor-unit1", MTypeName([], "unit")), $3)) }
  | CONSTRUCTOR { make_standard (TokArg $1) (TokArg $1)
                    (UTVariantCons(extract_name $1, (Range.dummy "dec-constructor-unit2", MTypeName([], "unit")), (Range.dummy "end-of-variant2", UTEndOfVariant))) }
/* -- for syntax error log -- */
  | CONSTRUCTOR OF error            { report_error (Tok $2) "of" }
  | CONSTRUCTOR OF txfunc BAR error { report_error (Tok $4) "|" }
/* -- -- */
;
txfunc: /* -> manual_type */
  | txprod ARROW txfunc {
        let rng = make_range (ManuType $1) (ManuType $3) in (rng, MFuncType($1, $3)) }
  | txprod { $1 }
/* -- for syntax error log -- */
  | txprod ARROW error { report_error (Tok $2) "->" }
/* -- -- */
;
txprod: /* -> manual_type */
  | txapppre TIMES txprod {
        let rng = make_range (ManuType $1) (ManuType $3) in
          match $3 with
          | (_, MProductType(tylist)) -> (rng, MProductType($1 :: tylist))
          | other                     -> (rng, MProductType([$1; $3]))
      }
  | txapppre { $1 }
/* -- for syntax error log -- */
  | txapppre TIMES error { report_error (Tok $2) "*" }
/* -- -- */
;
txapppre: /* -> manual_type */
  | txapp {
          match $1 with
          | (lst, (rng, MTypeName([], tynm))) -> (rng, MTypeName(lst, tynm))
          | ([], mnty)                        -> mnty
          | _                                 -> assert false
      }
  | LPAREN txfunc RPAREN { $2 }
  | TYPEVAR {
        let (rng, tyargnm) = $1 in (rng, MTypeParam(tyargnm))
      }
;
txapp: /* manual_type list * manual_type */
  | txbot txapp                { let (lst, mnty) = $2 in ($1 :: lst, mnty) }
  | LPAREN txfunc RPAREN txapp { let (lst, mnty) = $4 in ($2 :: lst, mnty) }
  | TYPEVAR txapp              {
        let (rng, tyargnm) = $1 in
        let (lst, mnty) = $2 in
          ((rng, MTypeParam(tyargnm)) :: lst, mnty)
      }
  | txbot                      { ([], $1) }
;
txbot: /* -> manual_type */
  | VAR {
        let (rng, tynm) = $1 in (rng, MTypeName([], tynm))
      }
  | CONSTRUCTOR DOT VAR {
        let (rng1, mdlnm) = $1 in
        let (rng2, tynm)  = $3 in
        let rng = make_range (Rng rng1) (Rng rng2) in
          (rng, MTypeName([], mdlnm ^ "." ^ tynm))
      }
  | BRECORD txrecord ERECORD {
        let asc = Assoc.of_list $2 in
        let rng = make_range (Tok $1) (Tok $3) in
          (rng, MRecordType(asc))
  }
/* -- for syntax error log -- */
  | CONSTRUCTOR DOT error { report_error (Tok $2) "." }
  | BRECORD error         { report_error (Tok $1) "(|" }
/* -- -- */
;
txrecord: /* -> (field_name * manual_type) list */
  | VAR COLON txfunc LISTPUNCT txrecord { let (_, fldnm) = $1 in (fldnm, $3) :: $5 }
  | VAR COLON txfunc LISTPUNCT          { let (_, fldnm) = $1 in (fldnm, $3) :: [] }
  | VAR COLON txfunc                    { let (_, fldnm) = $1 in (fldnm, $3) :: [] }
/* -- for syntax error log -- */
  | VAR COLON error                  { let (_, fldnm) = $1 in report_error (TokArg $1) (fldnm ^ " : ") }
  | VAR COLON txfunc LISTPUNCT error { report_error (Tok $4) ";" }
/* -- -- */
;
tuple: /* -> untyped_tuple_cons */
  | nxlet             { make_standard (Untyped $1) (Untyped $1) (UTTupleCons($1, (Range.dummy "end-of-tuple'", UTEndOfTuple))) }
  | nxlet COMMA tuple { make_standard (Untyped $1) (Untyped $3) (UTTupleCons($1, $3)) }
/* -- for syntax error log -- */
  | nxlet COMMA error { report_error (Tok $2) "," }
/* -- -- */
;
pats: /* -> code_range * untyped_patter_match_cons */
  | patas ARROW nxletsub {
        let (lastrng, _) = $3 in
          (lastrng, UTPatternMatchCons($1, $3, UTEndOfPatternMatch)) }
  | patas ARROW nxletsub BAR pats {
        let (lastrng, pmcons) = $5 in
          (lastrng, UTPatternMatchCons($1, $3, pmcons)) }
  | patas WHEN nxletsub ARROW nxletsub {
        let (lastrng, _) = $5 in
          (lastrng, UTPatternMatchConsWhen($1, $3, $5, UTEndOfPatternMatch)) }
  | patas WHEN nxletsub ARROW nxletsub BAR pats {
        let (lastrng, pmcons) = $7 in
          (lastrng, UTPatternMatchConsWhen($1, $3, $5, pmcons)) }
/* -- for syntax error log -- */
  | patas ARROW error                            { report_error (Tok $2) "->" }
  | patas ARROW nxletsub BAR error               { report_error (Tok $4) "|" }
  | patas WHEN error                             { report_error (Tok $2) "when" }
  | patas WHEN nxletsub ARROW error              { report_error (Tok $4) "->" }
  | patas WHEN nxletsub ARROW nxletsub BAR error { report_error (Tok $6) "|" }
/* -- -- */
;
patas:
  | pattr AS VAR       { make_standard (Pat $1) (TokArg $3) (UTPAsVariable(extract_name $3, $1)) }
  | pattr              { $1 }
/* -- for syntax error log -- */
  | pattr AS error   { report_error (Tok $2) "as" }
/* -- -- */
;
pattr: /* -> Types.untyped_pattern_tree */
  | patbot CONS pattr  { make_standard (Pat $1) (Pat $3) (UTPListCons($1, $3)) }
  | CONSTRUCTOR patbot { make_standard (TokArg $1) (Pat $2) (UTPConstructor(extract_name $1, $2)) }
  | CONSTRUCTOR        { make_standard (TokArg $1) (TokArg $1) (UTPConstructor(extract_name $1, (Range.dummy "constructor-unit-value", UTPUnitConstant))) }
  | patbot             { $1 }
/* -- for syntax error log -- */
  | patbot CONS error { report_error (Tok $2) "::" }
  | CONSTRUCTOR error { report_error (TokArg $1) "" }
/* -- -- */
;
patbot: /* -> Types.untyped_pattern_tree */
  | NUMCONST           { make_standard (TokArg $1) (TokArg $1) (UTPNumericConstant(int_of_string (extract_name $1))) }
  | TRUE               { make_standard (Tok $1) (Tok $1) (UTPBooleanConstant(true)) }
  | FALSE              { make_standard (Tok $1) (Tok $1) (UTPBooleanConstant(false)) }
  | UNITVALUE          { make_standard (Tok $1) (Tok $1) UTPUnitConstant }
  | WILDCARD           { make_standard (Tok $1) (Tok $1) UTPWildCard }
  | VAR                { make_standard (TokArg $1) (TokArg $1) (UTPVariable(extract_name $1)) }
  | LPAREN patas RPAREN                { make_standard (Tok $1) (Tok $3) (extract_main $2) }
  | LPAREN patas COMMA pattuple RPAREN { make_standard (Tok $1) (Tok $5) (UTPTupleCons($2, $4)) }
  | BLIST ELIST                        { make_standard (Tok $1) (Tok $2) UTPEndOfList }
  | OPENQT sxblock CLOSEQT {
        let rng = make_range (Tok $1) (Tok $3) in (rng, UTPStringConstant(rng, omit_spaces $2)) }
/* -- for syntax error log -- */
  | LPAREN error             { report_error (Tok $1) "(" }
  | LPAREN patas COMMA error { report_error (Tok $3) "," }
  | BLIST error              { report_error (Tok $1) "[" }
  | OPENQT error             { report_error (Tok $1) "`" }
/* -- -- */
patbotwithoutvar: /* -> Types.untyped_pattern_tree */
  | NUMCONST           { make_standard (TokArg $1) (TokArg $1) (UTPNumericConstant(int_of_string (extract_name $1))) }
  | TRUE               { make_standard (Tok $1) (Tok $1) (UTPBooleanConstant(true)) }
  | FALSE              { make_standard (Tok $1) (Tok $1) (UTPBooleanConstant(false)) }
  | UNITVALUE          { make_standard (Tok $1) (Tok $1) UTPUnitConstant }
  | WILDCARD           { make_standard (Tok $1) (Tok $1) UTPWildCard }
  | LPAREN patas RPAREN                { make_standard (Tok $1) (Tok $3) (extract_main $2) }
  | LPAREN patas COMMA pattuple RPAREN { make_standard (Tok $1) (Tok $5) (UTPTupleCons($2, $4)) }
  | BLIST ELIST                        { make_standard (Tok $1) (Tok $2) UTPEndOfList }
  | OPENQT sxblock CLOSEQT {
        let rng = make_range (Tok $1) (Tok $3) in (rng, UTPStringConstant(rng, omit_spaces $2)) }
/* -- for syntax error log -- */
  | LPAREN error             { report_error (Tok $1) "(" }
  | LPAREN patas COMMA error { report_error (Tok $3) "," }
  | BLIST error              { report_error (Tok $1) "[" }
  | OPENQT error             { report_error (Tok $1) "`" }
/* -- -- */
;
pattuple: /* -> untyped_pattern_tree */
  | patas                { make_standard (Pat $1) (Pat $1) (UTPTupleCons($1, (Range.dummy "end-of-tuple-pattern", UTPEndOfTuple))) }
  | patas COMMA pattuple { make_standard (Pat $1) (Pat $3) (UTPTupleCons($1, $3)) }
/* -- for syntax error log -- */
  | patas COMMA error    { report_error (Tok $2) "," }
/* -- -- */
;
binop:
  | PLUS    { "+" }      | MINUS   { "-" }      | MOD     { "mod" }
  | TIMES   { "*" }      | DIVIDES { "/" }      | CONCAT  { "^" }
  | EQ      { "==" }     | NEQ     { "<>" }     | GEQ     { ">=" }
  | LEQ     { "<=" }     | GT      { ">" }      | LT      { "<" }
  | LAND    { "&&" }     | LOR     { "||" }     | LNOT    { "not" }
  | BEFORE  { "before" }
;
sxsep:
  | SEP sxsepsub { $2 }
  | sxblock      { $1 }
  | sxitemize    { make_list_to_itemize $1 }
/* -- for syntax error log -- */
  | SEP error    { report_error (Tok $1) "|" }
/* -- -- */
;
sxitemize:
  | ITEM sxblock sxitemize {
      let (rng, depth) = $1 in
        (rng, depth, $2) :: $3
    }
  | ITEM sxblock {
      let (rng, depth) = $1 in
        (rng, depth, $2) :: []
}
;
sxsepsub:
  | sxblock SEP sxsepsub { make_standard (Untyped $1) (Untyped $3) (UTListCons($1, $3)) }
  |                      { (Range.dummy "end-of-string-list", UTEndOfList) }
/* -- for syntax error log -- */
  | sxblock SEP error    { report_error (Tok $2) "|" }
/* -- -- */
;
sxblock:
  | sxbot sxblock { make_standard (Untyped $1) (Untyped $2) (UTConcat($1, $2)) }
  |               { (Range.dummy "string-empty", UTStringEmpty) }
;
sxbot:
  | CHAR  { let (rng, ch) = $1 in (rng, UTStringConstant(ch)) }
  | SPACE { let rng = $1 in (rng, UTStringConstant(" ")) }
  | BREAK { let rng = $1 in (rng, UTBreakAndIndent) }
  | VARINSTR ENDACTIVE { make_standard (TokArg $1) (Tok $2) (UTContentOf([], extract_name $1)) }
  | CTRLSEQ sxclsnm sxidnm narg sarg {
        let (csrng, csnm) = $1 in
          convert_into_apply (csrng, UTContentOf([], csnm)) $2 $3 (append_argument_list $4 $5)
      }
  | CTRLSEQWITHMOD sxclsnm sxidnm narg sarg {
        let (csrng, mdlnmlst, csnm) = $1 in
          convert_into_apply (csrng, UTContentOf(mdlnmlst, csnm)) $2 $3 (append_argument_list $4 $5)
      }
/* -- for syntax error log -- */
  | VARINSTR error { report_error (TokArg $1) "" }
  | CTRLSEQ error  { report_error (TokArg $1) "" }
/* -- -- */
sxclsnm:
  | CLASSNAME { make_standard (TokArg $1) (TokArg $1) (class_name_to_abstract_tree (extract_name $1)) }
  |           { (Range.dummy "no-class-name1", UTConstructor("Nothing", (Range.dummy "no-class-name2", UTUnitConstant))) }
sxidnm:
  | IDNAME    { make_standard (TokArg $1) (TokArg $1) (id_name_to_abstract_tree (extract_name $1)) }
  |           { (Range.dummy "no-id-name1", UTConstructor("Nothing", (Range.dummy "no-id-name2", UTUnitConstant))) }
;
narg: /* -> untyped_argument_cons */
  | OPENNUM nxlet CLOSENUM narg { let rng = make_range (Tok $1) (Tok $3) in (rng, extract_main $2) :: $4 }
  | OPENNUM CLOSENUM narg       { let rng = make_range (Tok $1) (Tok $2) in (rng, UTUnitConstant) :: $3 }
  | OPENNUM_AND_BRECORD nxrecord CLOSENUM_AND_ERECORD narg {
        let rng = make_range (Tok $1) (Tok $3) in (rng, UTRecord($2)) :: $4
      }
  | OPENNUM_AND_BLIST nxlist CLOSENUM_AND_ELIST narg {
        let rng = make_range (Tok $1) (Tok $3) in (rng, extract_main $2) :: $4
      }
  |                             { end_of_argument }
/* -- for syntax error log -- */
  | OPENNUM error                { report_error (Tok $1) "( (in active area)" }
  | OPENNUM nxlet CLOSENUM error { report_error (Tok $3) ") (in active area)" }
  | OPENNUM_AND_BRECORD error    { report_error (Tok $1) "(| (in active area)" }
  | OPENNUM_AND_BRECORD nxrecord CLOSENUM_AND_ERECORD error { report_error (Tok $3) "|) (in active area)" }
  | OPENNUM_AND_BLIST error      { report_error (Tok $1) "[ (in active area)" }
  | OPENNUM_AND_BLIST nxlist CLOSENUM_AND_ELIST error { report_error (Tok $3) "] (in active area)" }
/* -- -- */
;
sarg: /* -> Types.untyped_argument_cons */
  | BGRP sxsep EGRP sargsub        { let rng = make_range (Tok $1) (Tok $3) in (rng, extract_main $2) :: $4 }
  | OPENQT sxblock CLOSEQT sargsub { let rng = make_range (Tok $1) (Tok $3) in (rng, omit_spaces $2) :: $4 }
  | ENDACTIVE                      { end_of_argument }
/* -- for syntax error log --*/
  | BGRP error            { report_error (Tok $1) "{" }
  | BGRP sxsep EGRP error { report_error (Tok $3) "}" }
/* -- -- */
;
sargsub: /* -> Types.argument_cons */
  | BGRP sxsep EGRP sargsub        { let rng = make_range (Tok $1) (Tok $3) in (rng, extract_main $2) :: $4 }
  | OPENQT sxblock CLOSEQT sargsub { let rng = make_range (Tok $1) (Tok $3) in (rng, omit_spaces $2) :: $4 }
  |                                { end_of_argument }
/* -- for syntax error log -- */
  | BGRP error                   { report_error (Tok $1) "{" }
  | BGRP sxsep EGRP error        { report_error (Tok $3) "}" }
  | OPENQT error                 { report_error (Tok $1) "`" }
  | OPENQT sxblock CLOSEQT error { report_error (Tok $3) "`" }
/* -- -- */
;