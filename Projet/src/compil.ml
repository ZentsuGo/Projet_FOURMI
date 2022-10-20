open Ast;;
open Printf;;
open CodeMap;;

type value_env = (string * value) list
type function_env = (string * (string list) * program) list (* nom de la fct, les arguments en nom pour remplacer, le label *)
type environment = value_env * function_env


let bind_value (str:string) (v:value) (env:environment) : environment =
        let (val_env, fun_env) = env in ((str,v)::val_env, fun_env)

(** *)
let process_sensedir (sensed : sensedir) : string = match sensed with
  | LeftAhead -> "LeftAhead"
  | RightAhead -> "RightAhead"
  | Here -> "Here"
  | Ahead -> "Ahead"

(** Parcours l'environnement de fonction pour récupérer la liste des arguments et le corps associé *)
let rec get_func_from_name (name:string) (val_env, fun_env : environment) : (string list) * program = match fun_env with
  |[] -> failwith "Fonction non existante..."
  |(str,_,_)::q when str <> name -> get_func_from_name name (val_env, q) 
  |(_,arg_list, prog)::_ -> arg_list,prog

  (** Ajoute à l'environnement les valeurs des arguments (en associant les noms aux valeurs évaluées)*)
let rec update_env_for_fun (arg_names:string list) (arg_values: value list) (val_env, fun_env: environment) : environment =
        match arg_names,arg_values with
        |[],[] ->  (val_env,fun_env)
        |[],_ | _, [] -> failwith "Eh ? Pas le même nombre"
        |name::qname, value::qvalue ->
                let new_val_env,new_fun_env = update_env_for_fun qname qvalue (val_env,fun_env) in
                ((name,value)::new_val_env, new_fun_env)

let rec eval (expr : expression Span.located) (env : environment) (file : out_channel) : value * environment =
        match expr with
        | Const(v, _), _ ->  v, env
        | Var((str, _), exprsp), _ ->
                let (v, new_env) = eval exprsp env file in (Unit, bind_value str v new_env)
        | Compare(comp, sp), _ ->
                let bool_val,new_env = (process_compare comp env file) in
                        (match bool_val with
                        | true -> Bool(True, sp), new_env
                        | false -> Bool(False, sp), new_env)
        | Operation(op, _), _ -> (process_operation op env file)
        | Command(cmd, _), _ -> let value,new_env = (process_command cmd env file) in value, new_env
        (*If et Else sont gérés dans process_program pour prévoir 2 expressions*)
        | While((exp, spe), (prog, spp)), _ ->
                let bool_val, new_env = eval (exp, spe) env file in
                (match bool_val with
                | Bool(True, _) -> (match exp with
                | Const(Bool(True, spb), _) -> 
                        Span.print spb stderr; failwith "[Type Error] :\
                                 infinite while loop.\n" (*cas while(true)*)
                | _ -> let value, new_env2 = process_program prog new_env file in (match value with
                | Unit -> eval expr new_env2 file (*on réevalue toute l'expression dans le nouvel environnement*)
                | _ -> Span.print spp stderr; failwith "[Type Error] :\
                         Inside while loop expression is not type unit.\n")) 
                | Bool(False, _) -> Unit, env
                | _ -> Span.print spe stderr; failwith "[Type Error] :\
                         the return value of the expression is not a boolean.\n")
        | DoWhile((prog, spp), (exp, spe)), _ ->
                let value, new_env = process_program prog env file in
                (match value with
                | Unit -> let bool_val, new_env2 = eval (exp, spe) new_env file in (match bool_val with
                | Bool(True, _) -> (match exp with
                 | Const(Bool(True, _), _) -> Span.print spp stderr; failwith "[Type Error] :\
                         infinite dowhile loop.\n"
                | _ -> eval expr new_env2 file) (*on réevalue toute l'expression dans le nouvel environnement new_env2*)
                | Bool(False, sp) -> Unit, env
                | _ -> Span.print spe stderr; failwith "[Type Error] :\
                        the return value of the expression is not a boolean.\n")
                | _ -> Span.print spp stderr; failwith "[Type Error] :\
                        Inside do while loop the expression is not type unit.\n")
        | Apply((name,_), (args_expr,_)),_ -> process_apply name args_expr env file
        (*Func est déjà traité dans la fonction start_program*)
        | _ -> failwith "WIP"

and process_condition (condi : cond) (env : environment) (file_out : out_channel) : string * environment = match condi with
  | Friend -> "Friend", env
  | Foe -> "Foe", env
  | FriendWithFood -> "FriendWithFood", env
  | FoeWithFood -> "FoeWithFood", env
  | Food -> "Food", env
  | Rock -> "Rock", env
  | Marker(expr)  ->
        let value, new_env = (eval expr env file_out) in
        (match value with
        | Int(k, _) -> "Marker "^(Int.to_string k), new_env
        | _ -> failwith "[Type Error] : the marker's expression return value type is not integer.\n")
  | FoeMarker -> "FoeMarker",env
  | Home -> "Home", env
  | FoeHome -> "FoeHome", env

and process_operation (op : operation) (env : environment) (file : out_channel) : value * environment =
        match op with
        | Add((v1, sp), (v2, sp2)) ->
                let value, new_env = (eval (v1, sp) env file) in
                let value2, new_env2 = (eval (v2, sp2) new_env file) in
                        (match value, value2 with
                        | Int(i, spp), Int(y, _) -> Int(i + y, spp), new_env2
                        | _, _ -> Span.print sp stderr; failwith "[Type Error] :\
                                there was an error while trying to sum up two values.\n")
| Sub((v1, sp), (v2, sp2)) ->
        let value, new_env = (eval (v1, sp) env file) in
        let value2, new_env2 = (eval (v2, sp2) new_env file) in
                (match value, value2 with
                | Int(i, spp), Int(y, _) -> Int(i - y, spp), new_env2
                | _, _ -> Span.print sp stderr; failwith "[Type Error] :\
                         there was an error while trying to substract two values.\n")
| Mul((v1, sp), (v2, sp2)) ->
        let value, new_env = (eval (v1, sp) env file) in
        let value2, new_env2 = (eval (v2, sp2) new_env file) in
                (match value, value2 with
                | Int(i, spp), Int(y, _) -> Int(i * y, spp), new_env2
                | _, _ -> Span.print sp stderr; failwith "[Type Error] :\
                         there was an error while trying to multiply two values.\n")
| Div((v1, sp), (v2, sp2)) ->
        let value, new_env = (eval (v1, sp) env file) in
        let value2, new_env2 = (eval (v2, sp2) new_env file) in
                (match value, value2 with
                | Int(i, spp), Int(y, _) -> Int(i / y, spp), new_env2
                | _, _ -> Span.print sp stderr; failwith "[Type Error] :\
                         there was an error while trying to divide two values.\n")
| Mod((v1, sp), (v2, sp2)) ->
        let value, new_env = (eval (v1, sp) env file) in
        let value2, new_env2 = (eval (v2, sp2) new_env file) in
        (match value, value2 with
                | Int(i, spp), Int(y, _) -> Int(i mod y, spp), new_env2
                | _, _ -> Span.print sp stderr; failwith "[Type Error] :\
                         there was an error while trying to use modulo.\n")

and process_program (Program(program) : Ast.program) (env : environment) (file : out_channel) : value * environment = 
  match program with
    |[],_ -> Unit, env
    |expr_fst::expr_scd::q, sp ->(
        match expr_fst, expr_scd with
        | (If((cond, spc), (prog_if, _)), _), (Else(prog_el, _), _) -> (*cas if else qui doit prendre en compte 2 expressions*)
                let bool_value, new_env = eval (cond, spc) env file in
                        (match bool_value with
                        (*si la condition cond est vraie*)
                        | Bool(True, _) -> process_program prog_if new_env file (*on évalue le bloc if dans new_env*) 
                        (*sinon si cond fausse*)
                        | Bool(False, _) -> process_program prog_el new_env file (*on évalue le bloc else dans new_env*)
                        | _ -> Span.print spc stderr; failwith "[Type Error] :\
                        the return value of the expression is not a boolean.\n")
        | _, _ -> let value, new_env = eval expr_fst env file in (*exécution de la première expression si ce n'est pas de la forme if else*)
                (match value with
                | Unit -> (process_program (Program(q, sp)) new_env file)
                | _ -> if q <> [] then failwith "[Type Error] :\
                        There is a non-last return value that is not type unit.\n"
                else value, new_env))
    |expr::q, sp -> let value, new_env = eval expr env file in (*évaluation cas une expression*)
        match value with
        | Unit -> (process_program (Program(q, sp)) new_env file)
        | _ -> if q <> [] then failwith "[Type Error] :\
                 There is a non-last return value that is not type unit.\n"
              else value, new_env (*On utilise un comportement similaire à Caml qui retourne la dernière valeur qui n'est pas de type unit.*)

and process_compare (comp : compare) (env:environment) (file : out_channel) : bool*environment = match comp with
| Eq(expr_left, expr_right) ->  let v1,new_env = eval (expr_left) env file in (*check type != unit*)
                                let v2,new_env2 = eval (expr_right) new_env file in
                                if v1=v2 then true,new_env2
                                else false,new_env2
| Inf(expr_left, expr_right) -> let v1,new_env = eval (expr_left) env file in
                                let v2,new_env2 = eval (expr_right) new_env file in
                                if v1<=v2 then true,new_env2
                                else false,new_env2
| Sup(expr_left, expr_right) -> let v1,new_env = eval (expr_left) env file in
                                let v2,new_env2 = eval (expr_right) new_env file in
                                if v1>=v2 then true,new_env2
                                else false,new_env2
| StInf(expr_left, expr_right) ->  let v1,new_env = eval (expr_left) env file in
                                let v2,new_env2 = eval (expr_right) new_env file in
                                if v1>v2 then true,new_env2
                                else false,new_env2
| StSup(expr_left, expr_right) ->  let v1,new_env = eval (expr_left) env file in
                                let v2,new_env2 = eval (expr_right) new_env file in
                                if v1>v2 then true,new_env2
                                else false,new_env2

and eval_list (list: (expression Span.located) list) (env: environment) (file: out_channel) : value list * environment = 
  let new_env = ref env in
  let rec aux l = match l with
        | [] -> []
        | exp::q -> let v, temp_env = eval exp (!new_env) file in
                        new_env := temp_env; v::(aux q)
  in (aux list, !new_env)

(** On traite les mouvements élémentaires des fourmis.
    ATTENTION : on ne va pas changer l'environnement pour les fonctions avec des callbacks ie Move, Pickup, Sense, Flip
    On renvoit la valeur de retour potentiel des fonctions appelées ainsi que l'environnement potentiellement modifié par Mark par exemple*)
and process_command (cmd: command) (env: environment) (file: out_channel) : value * environment =
        match cmd with
	| Move((name,_), (arg_list,_)) -> 
        let current_label,goto_label,_,_ = process_apply_nowrite name arg_list env file in
        fprintf file "\tMove %s\n" goto_label ; (* On écrit le move avec le potentiel appel*)
        fprintf file "\tGoto %s\n" current_label; (* On exécute la suite si on a pas eu d'appel *)
        fprintf file "%s:\n" current_label; (* Le label de retour dans tout les cas (le goto précédent ainsi que le retour de la fonction) *)

        Unit, env (* Obliger de renvoyer Unit comme on ne peut pas déterminer statiquement. 
       On ne prend pas en compte le changement d'environnement comme on est pas sûr à la compil du changement *)
	| Mark(expr, sp) -> ((*i représente le ième bit à modifier sur la case marquée*)
        let value, new_env = eval (expr,sp) env file in match value with
          | Int(i,_) -> fprintf file "\tMark %d\n" i ; Unit, new_env
          | _ -> Span.print sp stderr ; failwith "[Type Error] : there was an error marking : type is not an int")
	| Unmark(expr, sp) -> ((*de même pour unmark*)
        let value, new_env = eval (expr,sp) env file in match value with 
          | Int(i,_) -> fprintf file "\tUnmark %d\n" i; Unit, new_env
          | _ -> Span.print sp stderr ; failwith "[Type Error] : there was an error unmarking : type is not an int")
	| Pickup((fun_name,_), (arg_list,_)) ->
                let value,new_env = process_apply fun_name arg_list env file in value,new_env (* Ecrire le Pickup *)
	| Turn(dir, _) -> (*dir représente la direction dans laquelle la fourmi va tourner*)
        (match dir with
                | Left -> fprintf file "\tTurn Left\n"
                | Right -> fprintf file "\tTurn Right\n");
        Unit,env
	| Sense((sensd,_), (condition,_) , (name_true,_), (arg_list_true,_), (name_false,_), (arg_list_false,_)) ->  (* Sense va, selon la condition et pour une direction sensd donnée, évaluer la fonction func_name_true sur arg_list_true ou func_name_false sur arg_list_false*)
                let current_label_true,goto_label_true,_,_ = process_apply_nowrite name_true arg_list_true env file in
                let current_label_false,goto_label_false,_,_ = process_apply_nowrite name_false arg_list_false env file in
                let str_cond,new_env = process_condition condition env file in
                fprintf file "\tSense %s %s %s %s\n" (process_sensedir sensd) goto_label_true goto_label_false str_cond ;
                fprintf file "\tGoto %s\n" current_label_true ; (* On veut rentrer au même endroit mais les fonctions elles ne reviennent pas au même endroit *)
                fprintf file "%s: \n" current_label_false ; (* On choisit arbitrairement que le true sera la suite du programme général *)
                fprintf file "\tGoto %s\n" current_label_true ; (* Depuis le retour du false, on saute directement au retour de true, la suite*)
                fprintf file "%s: \n" current_label_true ;
                Unit,new_env
        | Flip((expr_i,sp), (name_true,_), (arg_list_true,_),(name_false,_),(arg_list_false,_)) ->
                (let current_label_true,goto_label_true,_,_ = process_apply_nowrite name_true arg_list_true env file in
                let current_label_false,goto_label_false,_,_ = process_apply_nowrite name_false arg_list_false env file in
                let value, new_env = eval (expr_i,sp) env file in 
                let val_i = (match value with
                        |Int(i,_) -> i
                        |_ -> Span.print sp stderr ; failwith "[Type Error] : Flip argument wasn't an int") in
                fprintf file "\tFlip %i %s %s\n" val_i goto_label_true goto_label_false;
                fprintf file "\tGoto %s\n" current_label_true ; (* On veut rentrer au même endroit mais les fonctions elles ne reviennent pas au même endroit *)
                fprintf file "%s: \n" current_label_false ; (* On choisit arbitrairement que le true sera la suite du programme général *)
                fprintf file "\tGoto %s\n" current_label_true ; (* Depuis le retour du false, on saute directement au retour de true, la suite*)
                fprintf file "%s: \n" current_label_true ;
                Unit,new_env)
  | Drop -> fprintf file "\tDrop\n" ; Unit,env

(** On traite le cas Apply d'appel d'une fonction name avec les arguments args_expr sous forme d'expression dans l'environnement spécifié
  On va rajouter des labels pour s'occuper des sauts avant et après *)
and process_apply (name:string) (args_expr:expression Span.located list) (val_env,fun_env:environment) (file : out_channel) : value * environment = 
  let arg_names,prog = get_func_from_name name (val_env,fun_env) in (* On récupère les informations de la fonction *)
  let (arg_values,(new_val_env,new_fun_env)) = eval_list args_expr  (val_env,fun_env) file in (* On évalue nos arguments *)
  let apply_val_env,apply_fun_env = update_env_for_fun arg_names arg_values  (new_val_env,new_fun_env) in (* On met à jour l'environnement avec les arguments pour la fonction*)
  
  (* Il faut écrire le goto avec le nouveau label, le nouveau label quelque part (dans un tout nouveau fichier unique à chaque fois que l'on re-fusionne à la fin) *)
  let current_label,goto_label,v,post_env = create_fun_label name prog (apply_val_env, apply_fun_env) in

  fprintf file "Goto %s \n\t" goto_label ; (* On fait "l'appel" à la fonction en allant à son label *)
  fprintf file "%s:\n\t" (current_label) ; (* On écrit dans le fichier le label de retour de la fonction ici *)
  
  v, post_env

and process_apply_nowrite (name:string) (args_expr:expression Span.located list) ((val_env,fun_env):environment) (file : out_channel) : string * string *value * environment = 
  let arg_names,prog = get_func_from_name name (val_env,fun_env) in (* On récupère les informations de la fonction *)
  let (arg_values,(new_val_env,new_fun_env)) =
  eval_list args_expr (val_env,fun_env) file in (* On évalue nos arguments *)
  let apply_val_env,apply_fun_env =
  update_env_for_fun arg_names arg_values  (new_val_env,new_fun_env) in (* On met à jour l'environnement avec les arguments pour la fonction*)
  (* Il faut écrire le goto avec le nouveau label, le nouveau label quelque part (dans un tout nouveau fichier unique à chaque fois que l'on re-fusionne à la fin) *)
  create_fun_label name prog (apply_val_env, apply_fun_env)


(** Crée le label de la fonction associée avec ses arguments dans un autre fichier et 
    renvoie le nom du label crée ainsi que le label du retour (current(original) * goto(la fonction)) et la valeur de retour et l'environnement après l'application de la fonction*)
and create_fun_label (name : string) (prog:program) ((apply_val_env,apply_fun_env):environment): string*string*value*environment = 
  let time = Int.to_string (Float.to_int (Sys.time ())) in
  let goto_label = "fun_"^name^time in (* On crée un label unique de la future fonction (avec le temps) *)
  let current_label = "current_"^name^time in (* On crée le label de retour de la fonction (ici) *)
  
  let new_file = open_out_gen [Open_creat] 0o777 (goto_label^".temp") in (* On crée le flux pour le nouveau fichier *)
  fprintf new_file "%s:\n\t" (goto_label) ; (* On écrit au début du nouveau fichier le label associé à l'appel de la fonction *)
  let v,post_env = process_program prog (apply_val_env,apply_fun_env) new_file in (* On process ce qui signifie qu'on écrit le programme dans le fichier. L'environnement est *)
  fprintf new_file "Goto %s\n\t" (current_label) ; (* On écrit le goto de retour (comme le return) à la fin du nouveau fichier *)
  close_out new_file ;

  current_label,goto_label,v,post_env


let start_program (prog : program) (env: environment) (file_out : string) : unit = 
  let main_prog = ref prog in (*variable qui va se souvenir du programme de main*)
  let rec aux (Program(prog_bis) : program) (env_bis : environment) : environment =
    match prog_bis with
    | [], _ -> env_bis
    | p::next_prog, sp ->
      (match p with
      | Func((str, _), (args, _), (progg, _)),_ when str = "main" ->
        main_prog := progg; 
        let val_env, func_env = env_bis in (*on stocke toutes les déclarations de fonctions dans l'environnement*)
        aux (Program(next_prog, sp)) (val_env, (str, List.map (fun (str,_) -> str) args, progg)::func_env)
        | Func((str, _), (args, _), (progg, _)),_ ->
          let val_env, func_env = env_bis in (*on stocke toutes les déclarations de fonctions dans l'environnement*)
          aux (Program(next_prog, sp)) (val_env, (str, List.map (fun (str,_) -> str) args, progg)::func_env)
          | _ -> aux (Program(next_prog,sp)) env_bis)
  in let new_env = aux prog env in 
  let file = open_out "main.temp" in  (* Notre premier fichier d'écriture, a priori ce sera le main *)
  let _,_ = process_program (!main_prog) new_env file in (* évaluation de la fonction main*)
  let _ = Sys.command ("for f in *.temp; do cat $f >> "^file_out^"; done") in (* On concatène les fichiers .temp dans file_out*)
  close_out file (* On ferme le fichier qu'on avait ouvert *)