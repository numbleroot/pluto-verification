(* before shit broke loose
*)
(* Victor B. F. Gomes, University of Cambridge
   Martin Kleppmann, University of Cambridge
   Dominic P. Mulligan, University of Cambridge
   Alastair R. Beresford, University of Cambridge
*)

section\<open>Observed-Remove Set\<close>
 
text\<open>The ORSet is a well-known CRDT for implementing replicated sets, supporting two operations:
     the \emph{insertion} and \emph{deletion} of an arbitrary element in the shared set.\<close>

theory
  OR2
imports
  Network
begin

datatype ('id, 'a) operation = Add "'id" "'a" | Rem "'id set" "'a" | Append "'a" "'id" |
	Store "'a" "'id" "'id"

type_synonym ('id, 'a) state = "('a \<Rightarrow> 'id set) \<times> ('a \<rightharpoonup> 'id set)"

definition op_elem :: "('id, 'a) operation \<Rightarrow> 'a" where
  "op_elem oper \<equiv> case oper of Add i e \<Rightarrow> e | Rem is e \<Rightarrow> e | Append e m \<Rightarrow> e | Store e mo mn \<Rightarrow> e"

definition interpret_op :: "('id, 'a) operation \<Rightarrow> ('id, 'a) state \<rightharpoonup> ('id, 'a) state" ("\<langle>_\<rangle>" [0] 1000) where
  "interpret_op oper state \<equiv>
     let before = ((fst state) (op_elem oper));
         metadata  = case oper of 
           Add i e \<Rightarrow> before \<union> {i} | 
           Rem is e \<Rightarrow> before - is | 
           Append e i \<Rightarrow> before \<union> {i} | 
           Store e mo mn \<Rightarrow> insert mn (before - {mo});
         filesystem = case oper of 
           Add i e \<Rightarrow> (case snd state e of None \<Rightarrow> Some {} | Some f \<Rightarrow> Some f) | 
           Rem is e \<Rightarrow> (case snd state e of None \<Rightarrow> None | Some f \<Rightarrow> (case before - is = {} of True \<Rightarrow> None | False \<Rightarrow> Some(f - is))) |
					 Append e m \<Rightarrow> (case snd state e of None \<Rightarrow> Some {m} | Some f \<Rightarrow> Some (insert m f)) |
					 Store e mo mn \<Rightarrow> (case snd state e of None \<Rightarrow> Some {mn} | Some f \<Rightarrow> Some (insert mn (f - {mo})))
     in  Some ((fst state) ((op_elem oper) := metadata), (snd state) ((op_elem oper) := filesystem))"



definition valid_behaviours :: "('id, 'a) state \<Rightarrow> 'id \<times> ('id, 'a) operation \<Rightarrow> bool" where
  "valid_behaviours state msg \<equiv>
     case msg of
       (i, Add j e) \<Rightarrow> i = j |
       (i, Rem is e) \<Rightarrow> is = fst state e |
			 (i, Append e m) \<Rightarrow> i = m |
			 (i, Store e mo mn) \<Rightarrow> i = mn \<and> mo \<in> fst state e
"

locale orset = network_with_constrained_ops _ interpret_op "(\<lambda>x. {}, \<lambda>y. None)" valid_behaviours

lemma (in orset) add_add_commute:
  shows "\<langle>Add i1 e1\<rangle> \<rhd> \<langle>Add i2 e2\<rangle> = \<langle>Add i2 e2\<rangle> \<rhd> \<langle>Add i1 e1\<rangle>"
  by(auto simp add: interpret_op_def op_elem_def kleisli_def, fastforce)

lemma add_rem_commute2:
fixes s
assumes "i \<notin> is"  and "e1 \<noteq> e2"
shows " (\<langle>Add i e1\<rangle> \<rhd> \<langle>Rem is e2\<rangle>) s = (\<langle>Rem is e2\<rangle> \<rhd> \<langle>Add i e1\<rangle>) s"
	unfolding interpret_op_def op_elem_def kleisli_def using assms apply simp
	by (smt bind_eq_Some_conv fst_conv fun_upd_other fun_upd_twist snd_conv)
 
lemma add_rem_commute3:
fixes s
assumes "i \<notin> is" and "case snd s e of Some f \<Rightarrow> f \<subseteq> fst s e | _ \<Rightarrow> True"
shows " (\<langle>Add i e\<rangle> \<rhd> \<langle>Rem is e\<rangle>) s = (\<langle>Rem is e\<rangle> \<rhd> \<langle>Add i e\<rangle>) s"
  unfolding interpret_op_def op_elem_def kleisli_def using assms apply simp apply (case_tac "snd s e = None") apply simp apply fastforce
  	apply simp
  by (smt Diff_eq_empty_iff bind_eq_Some_conv dual_order.trans fst_conv fun_upd_same fun_upd_upd insertI1 insert_Diff_if option.simps(4) option.simps(5) snd_conv subset_Compl_singleton)
  	
lemma (in orset) add_rem_commute:
assumes "i \<notin> is" and "case snd s e2 of Some f \<Rightarrow> f \<subseteq> fst s e2 | _ \<Rightarrow> True"
shows "(\<langle>Add i e1\<rangle> \<rhd> \<langle>Rem is e2\<rangle>) s = (\<langle>Rem is e2\<rangle> \<rhd> \<langle>Add i e1\<rangle>) s"
	using assms add_rem_commute3[of "i" "is" "s" "e1"] add_rem_commute2 [of "i" "is" "e1" "e2" "s"]
	by auto 
  	
lemma rem_rem_commute1:
	assumes "e1 \<noteq> e2"
	shows " (\<langle>Rem i1 e1\<rangle> \<rhd> \<langle>Rem i2 e2\<rangle>) s = (\<langle>Rem i2 e2\<rangle> \<rhd> \<langle>Rem i1 e1\<rangle>) s "
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "snd s e1 = None", simp) 
	 apply (smt assms bind_eq_Some_conv fst_conv fun_upd_other fun_upd_twist option.simps(4) snd_conv) apply simp
proof clarify
	fix y
		have A1 :"((let before = fst s e1
          in Some ((fst s)(e1 := before - i1), (snd s)
                   (e1 := case snd s e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1))))) \<bind>
         (\<lambda>y. let before = fst y e2
              in Some ((fst y)(e2 := before - i2), (snd y)
                       (e2 := case snd y e2 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2))))))
 = Some ((fst s)(e1 := (fst s e1 - i1), e2 := (fst s e2 - i2)), 
	(snd s)(
		e1 := (case snd s e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case fst s e1 - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1))), 
		e2 := (case snd s e2 of None \<Rightarrow> None | Some f \<Rightarrow> (case fst s e2 - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2)))))"
			by (smt assms bind_eq_Some_conv fst_conv fun_upd_other option.case_eq_if snd_conv)
		have "(let before = fst s e2
          in Some ((fst s)(e2 := before - i2), (snd s)
                   (e2 := case snd s e2 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2))))) \<bind>
         (\<lambda>y. let before = fst y e1
              in Some ((fst y)(e1 := before - i1), (snd y)
                       (e1 := case snd y e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1)))))
	= Some ((fst s)(e1 := (fst s e1 - i1), e2 := (fst s e2 - i2)), 
	(snd s)(
		e1 := (case snd s e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case fst s e1 - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1))), 
		e2 := (case snd s e2 of None \<Rightarrow> None | Some f \<Rightarrow> (case fst s e2 - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2)))))"
			by (smt assms bind.bind_lunit fst_conv fun_upd_other fun_upd_twist option.case_eq_if snd_conv)
 			
		thus "(let before = fst s e1
          in Some ((fst s)(e1 := before - i1), (snd s)
                   (e1 := case snd s e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1))))) \<bind>
         (\<lambda>y. let before = fst y e2
              in Some ((fst y)(e2 := before - i2), (snd y)
                       (e2 := case snd y e2 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2))))) =
         (let before = fst s e2
          in Some ((fst s)(e2 := before - i2), (snd s)
                   (e2 := case snd s e2 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2))))) \<bind>
         (\<lambda>y. let before = fst y e1
              in Some ((fst y)(e1 := before - i1), (snd y)
                       (e1 := case snd y e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1)))))"
      using A1 by auto
qed
  	
lemma rem_rem_commute2:
assumes "(snd s) e1 = None"
shows " (\<langle>Rem i1 e1\<rangle> \<rhd> \<langle>Rem i2 e1\<rangle>) s = (\<langle>Rem i2 e1\<rangle> \<rhd> \<langle>Rem i1 e1\<rangle>) s"
unfolding interpret_op_def kleisli_def op_elem_def using assms apply simp by fastforce
    	
lemma rem_rem_commute3:
assumes "(snd s) e1 \<noteq> None"
shows " (\<langle>Rem i1 e1\<rangle> \<rhd> \<langle>Rem i2 e1\<rangle>) s = (\<langle>Rem i2 e1\<rangle> \<rhd> \<langle>Rem i1 e1\<rangle>) s"
	unfolding interpret_op_def kleisli_def op_elem_def apply simp using assms 
		apply (case_tac "(fst s e1) - i1 = {}", simp) 
	 apply (smt Diff_eq_empty_iff Diff_subset bind.bind_lunit empty_subsetI fst_conv fun_upd_same fun_upd_upd option.simps(4) option.simps(5) snd_conv subset_trans)
	  apply (case_tac "(fst s e1) - i2 = {}", simp)
	 apply (smt Diff_disjoint Diff_eq Diff_eq_empty_iff Int_Diff bind.bind_lunit fst_conv fun_upd_same fun_upd_upd inf_commute option.simps(4) option.simps(5) snd_conv)
	apply (case_tac "((fst s e1) - i1 - i2) = {}", simp add:  Diff_eq fun_upd_same Diff_subset) 
	 apply (smt Diff_eq Int_assoc bind.bind_lunit fst_conv fun_upd_same fun_upd_upd inf_commute option.simps(5) snd_conv)
	 proof clarify
	fix y
	assume A1: "fst s e1 - i1 \<noteq> {}"
 "fst s e1 - i2 \<noteq> {}"
 "fst s e1 - i1 - i2 \<noteq> {}"
 "snd s e1 = Some y"
	 
have A2: "(let before = fst s e1
          in Some ((fst s)(e1 := before - i1), (snd s)
                   (e1 := case snd s e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1))))) \<bind>
         (\<lambda>y. let before = fst y e1
              in Some ((fst y)(e1 := before - i2), (snd y)
                       (e1 := case snd y e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2)))))
= Some (((fst s)(e1 := ((fst s e1) \<inter> - i1) \<inter> - i2)), (snd s) (e1 := Some(y - i1 - i2)) )" using A1 
	by (simp add: diff_eq)
		
have "(let before = fst s e1
          in Some ((fst s)(e1 := before - i2), (snd s)
                   (e1 := case snd s e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2))))) \<bind>
         (\<lambda>y. let before = fst y e1
              in Some ((fst y)(e1 := before - i1), (snd y)
                       (e1 := case snd y e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1)))))
= Some (((fst s)(e1 := ((fst s e1) \<inter> - i1) \<inter> - i2)), (snd s) (e1 := Some(y - i1 - i2)) )" using A1 apply (simp add: diff_eq) 
	by (smt Diff_Int2 Diff_Int_distrib2 diff_eq)
 
 thus "(let before = fst s e1
          in Some ((fst s)(e1 := before - i1), (snd s)
                   (e1 := case snd s e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1))))) \<bind>
         (\<lambda>y. let before = fst y e1
              in Some ((fst y)(e1 := before - i2), (snd y)
                       (e1 := case snd y e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2))))) =
         (let before = fst s e1
          in Some ((fst s)(e1 := before - i2), (snd s)
                   (e1 := case snd s e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i2 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i2))))) \<bind>
         (\<lambda>y. let before = fst y e1
              in Some ((fst y)(e1 := before - i1), (snd y)
                       (e1 := case snd y e1 of None \<Rightarrow> None | Some f \<Rightarrow> (case before - i1 = {} of True \<Rightarrow> None | False \<Rightarrow> Some (f - i1)))))"
   using A1 A2 by auto
qed
	
lemma rem_rem_commute:
shows " \<langle>Rem i1 e1\<rangle> \<rhd> \<langle>Rem i2 e2\<rangle> = \<langle>Rem i2 e2\<rangle> \<rhd> \<langle>Rem i1 e1\<rangle>"
proof
	fix x
	show "(\<langle>Rem i1 e1\<rangle> \<rhd> \<langle>Rem i2 e2\<rangle>) x = (\<langle>Rem i2 e2\<rangle> \<rhd> \<langle>Rem i1 e1\<rangle>) x"
		using rem_rem_commute1[of e1 e2 i1 i2 x] 
				  rem_rem_commute2[of x e1 i1 i2] 
          rem_rem_commute3[of x e1 i1 i2]
    by auto
qed 

lemma append_append_commute:
shows " \<langle>Append e1 m1\<rangle> \<rhd> \<langle>Append e2 m2\<rangle> = \<langle>Append e2 m2\<rangle> \<rhd> \<langle>Append e1 m1\<rangle>"
proof
	fix x
	show "(\<langle>Append e1 m1\<rangle> \<rhd> \<langle>Append e2 m2\<rangle>) x = (\<langle>Append e2 m2\<rangle> \<rhd> \<langle>Append e1 m1\<rangle>) x"
		unfolding interpret_op_def kleisli_def op_elem_def apply simp
		by (simp add: fun_upd_twist insert_commute option.case_eq_if)
qed  

lemma add_append_commute2:
	shows " (\<langle>Add i e1\<rangle> \<rhd> \<langle>Append e2 m2\<rangle>) x = (\<langle>Append e2 m2\<rangle> \<rhd> \<langle>Add i e1\<rangle>) x"
		unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1=e2") apply simp apply auto
			apply (simp add: insert_commute) apply (simp add: option.case_eq_if) by (simp add: fun_upd_twist)
			
lemma add_append_commute:
	shows " (\<langle>Add i e1\<rangle> \<rhd> \<langle>Append e2 m2\<rangle>) = (\<langle>Append e2 m2\<rangle> \<rhd> \<langle>Add i e1\<rangle>)"
	using add_append_commute2 proof qed
			
lemma rem_append_commute:
	assumes  "m2 \<notin> is" and "case snd x e2 of Some f \<Rightarrow> f \<subseteq> fst x e2 | _ \<Rightarrow> True" 
	shows " (\<langle>Rem is e1\<rangle> \<rhd> \<langle>Append e2 m2\<rangle>) x = (\<langle>Append e2 m2\<rangle> \<rhd> \<langle>Rem is e1\<rangle>) x"
		unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1 \<noteq> e2", simp) apply auto
		 apply (smt bind_eq_Some_conv fst_conv fun_upd_other fun_upd_twist snd_conv) using assms 
		apply (case_tac "(snd x e2) = None", simp) apply auto using assms apply simp 
		apply (simp add: insert_Diff_if) using assms apply simp 
		apply (simp add: Diff_eq option.case_eq_if)
			by (smt Diff_eq Diff_eq_empty_iff bind.bind_lunit fst_conv fun_upd_apply fun_upd_upd option.discI option.sel snd_conv subset_trans)		  
			
lemma store_store_commute:
	assumes  "mn1 \<noteq> mo2" and "mn2 \<noteq> mo1"
shows " (\<langle>Store e1 mo1 mn1\<rangle> \<rhd> \<langle>Store e2 mo2 mn2\<rangle>) x = (\<langle>Store e2 mo2 mn2\<rangle> \<rhd> \<langle>Store e1 mo1 mn1\<rangle>) x"
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1\<noteq>e2") apply simp apply auto using assms
		apply (simp add: fun_upd_twist) 
	using assms(1) assms(2) apply fastforce	 
  by (smt Diff_disjoint Diff_insert Int_Diff assms(1) assms(2) insert_Diff_if insert_commute option.case_eq_if option.simps(5) singletonD)
		
lemma store_add_commute:
assumes "i \<noteq> mo2"
shows " (\<langle>Add i e1\<rangle> \<rhd> \<langle>Store e2 mo2 mn2\<rangle>) x = (\<langle>Store e2 mo2 mn2\<rangle> \<rhd> \<langle>Add i e1\<rangle>) x"
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1=e2") apply simp apply auto 
	apply (simp add: assms(1) insert_Diff_if insert_commute) 
	apply (simp add: option.case_eq_if)
	by (simp add: fun_upd_twist)

lemma store_rem_commute:
	assumes "mn2 \<notin> is" and "case snd x e1 of Some f \<Rightarrow> f \<subseteq> fst x e1 | _ \<Rightarrow> True"
shows " (\<langle>Rem is e1\<rangle> \<rhd> \<langle>Store e2 mo2 mn2\<rangle>) x = (\<langle>Store e2 mo2 mn2\<rangle> \<rhd> \<langle>Rem is e1\<rangle>) x"
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1\<noteq>e2") apply simp apply auto
	using assms 
	 apply (smt bind_eq_Some_conv fst_conv fun_upd_other fun_upd_twist snd_conv) using assms 
	  	apply (case_tac "(snd x e2) = None", simp) apply auto using assms apply simp
	 apply fastforce using assms apply simp 
	  	apply (simp add: insert_Diff_if) using assms apply simp 
	apply (simp add: Diff_eq option.case_eq_if) apply (case_tac "fst x e2 \<subseteq> is") apply simp 
	apply (smt disjoint_eq_subset_Compl double_compl inf_le1 subset_trans) apply simp
	by fastforce
		
lemma store_append_commute:
	assumes "m \<noteq> mo2"
shows " (\<langle>Append e1 m\<rangle> \<rhd> \<langle>Store e2 mo2 mn2\<rangle>) x = (\<langle>Store e2 mo2 mn2\<rangle> \<rhd> \<langle>Append e1 m\<rangle>) x"
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1=e2") apply simp apply auto
		apply (simp add: assms insert_Diff_if insert_commute) 
	apply (simp add: assms insert_Diff_if insert_commute option.case_eq_if)
	by (simp add: fun_upd_twist)


		(*
lemma expunge_expunge_commute:
shows " (\<langle>Expunge e1 m1\<rangle> \<rhd> \<langle>Expunge e2 m2\<rangle>) x = (\<langle>Expunge e2 m2\<rangle> \<rhd> \<langle>Expunge e1 m1\<rangle>) x"
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1=e2") apply simp apply auto
	apply (case_tac "snd x e2 = None") by auto
		
lemma add_expunge_commute:
shows " (\<langle>Add i e1\<rangle> \<rhd> \<langle>Expunge e2 m2\<rangle>) x = (\<langle>Expunge e2 m2\<rangle> \<rhd> \<langle>Add i e1\<rangle>) x"
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1=e2") apply simp apply auto
	apply (case_tac "snd x e2 = None") by auto
		
lemma rem_expunge_commute:
	assumes "fst x e1 = {} \<Longrightarrow> snd x e1 = None"
shows " (\<langle>Rem is e1 m\<rangle> \<rhd> \<langle>Expunge e2 m2\<rangle>) x = (\<langle>Expunge e2 m2\<rangle> \<rhd> \<langle>Rem is e1 m\<rangle>) x"
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1=e2") apply simp apply auto
	apply (case_tac "snd x e2 = None") apply simp apply simp nitpick
		
lemma append_expunge_commute:
assumes "m1 \<noteq> m2"
shows " (\<langle>Append e1 m1\<rangle> \<rhd> \<langle>Expunge e2 m2\<rangle>) x = (\<langle>Expunge e2 m2\<rangle> \<rhd> \<langle>Append e1 m1\<rangle>) x"
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1=e2") apply simp apply auto
	apply (case_tac "snd x e2 = None") apply auto by (simp add: assms insert_Diff_if)
		
lemma store_expunge_commute:
assumes "m1n \<noteq> m2"
shows " (\<langle>Store e1 m1o m1n\<rangle> \<rhd> \<langle>Expunge e2 m2\<rangle>) x = (\<langle>Expunge e2 m2\<rangle> \<rhd> \<langle>Store e1 m1o m1n\<rangle>) x"
	unfolding interpret_op_def kleisli_def op_elem_def apply (case_tac "e1=e2") apply simp apply auto
	apply (case_tac "snd x e2 = None") apply auto using assms by fastforce

*)
		
lemma (in orset) apply_operations_never_fails:
  assumes "xs prefix of i"
  shows "apply_operations xs \<noteq> None"
using assms proof(induction xs rule: rev_induct, clarsimp)
  case (snoc x xs) thus ?case
  proof (cases x)
    case (Broadcast e) thus ?thesis
      using snoc by force
  next
    case (Deliver e) thus ?thesis
      using snoc by (simp, metis (no_types, lifting) bind.simps(2) interp_msg_def interpret_op_def prefix_of_appendD)
  qed
qed


lemma (in orset) apply_operations_invariant:
  assumes "xs prefix of i"
  and	"apply_operations xs = Some g"
  shows "case snd g e1 of Some f \<Rightarrow> f \<subseteq> fst g e1 | _ \<Rightarrow> True"
using assms proof (induct xs arbitrary: g rule: rev_induct, force)
  case (snoc x xs) thus ?case
  proof (cases x)
    case (Broadcast e) 
    thus ?thesis using snoc apply simp using snoc apply simp by blast
  next
    case (Deliver e)
    moreover obtain a b where "e = (a, b)" by force
    ultimately show ?thesis 
      using snoc apply(case_tac b; clarsimp simp: interp_msg_def split: bind_splits)
      	 apply (simp add: op_elem_def interpret_op_def)
      	apply (simp add: Diff_subset empty_subsetI fst_conv fun_upd_other fun_upd_same insertI1 insert_Diff_if insert_Diff_single insert_absorb insert_eq_iff option.case_eq_if option.sel prefix_of_appendD snd_conv subset_Compl_singleton subset_trans)
      	 apply (smt empty_iff fst_conv fun_upd_other fun_upd_same insertI2 option.discI option.sel snd_conv subset_iff)
      	apply (smt Diff_iff fst_conv fun_upd_other fun_upd_same interpret_op_def op_elem_def operation.case(2) option.case_eq_if option.sel prefix_of_appendD snd_conv subset_iff)
      	unfolding interpret_op_def apply simp
      	 apply (smt fst_conv fun_upd_other fun_upd_same insertE insertI1 insertI2 op_elem_def operation.simps(19) option.case_eq_if option.sel prefix_of_appendD singletonD snd_conv subset_iff)
      	  apply (simp add:  op_elem_def prefix_of_appendD subsetCE)        	apply (simp add: Diff_subset empty_subsetI fst_conv fun_upd_other fun_upd_same insertI1 insert_Diff_if insert_Diff_single insert_absorb insert_eq_iff option.case_eq_if option.sel prefix_of_appendD snd_conv subset_Compl_singleton subset_trans)
      	  by (smt Diff_iff empty_subsetI fst_conv fun_upd_other fun_upd_same insert_iff insert_subset option.discI option.sel snd_conv subset_iff)
  qed
qed

lemma (in orset) add_id_valid:
  assumes "xs prefix of j"
    and "Deliver (i1, Add i2 e) \<in> set xs"
  shows "i1 = i2"
proof -
  have "\<exists>s. valid_behaviours s (i1, Add i2 e)"
    using assms deliver_in_prefix_is_valid unfolding valid_behaviours_def by fastforce
  thus ?thesis
    by(simp add: valid_behaviours_def)
qed
	
lemma (in orset) append_id_valid:
  assumes "xs prefix of j"
    and "Deliver (i1, Append e i2) \<in> set xs"
  shows "i1 = i2"
proof -
  have "\<exists>s. valid_behaviours s (i1, Append e i2)"
    using assms deliver_in_prefix_is_valid unfolding valid_behaviours_def by fastforce
  thus ?thesis
    by(simp add: valid_behaviours_def)
qed
	
lemma (in orset) store_id_valid:
  assumes "xs prefix of j"
    and "Deliver (i1, Store e mo mn) \<in> set xs"
  shows "i1 = mn"
proof -
  have "\<exists>s. valid_behaviours s (i1, Store e mo mn)"
    using assms deliver_in_prefix_is_valid unfolding valid_behaviours_def by fastforce
  thus ?thesis
    by(simp add: valid_behaviours_def)
qed

definition (in orset) added_ids :: "('id \<times> ('id, 'b) operation) event list \<Rightarrow> 'b \<Rightarrow> 'id list" where
  "added_ids es p \<equiv> List.map_filter (\<lambda>x. case x of 
		Deliver (i, Add j e) \<Rightarrow> if e = p then Some j else None | 
		Deliver (i, Append e j) \<Rightarrow> if e = p then Some j else None |
		Deliver (i, Store e mo mn) \<Rightarrow> if e = p then Some mn else None |
		_ \<Rightarrow> None) es"

lemma (in orset) [simp]:
  shows "added_ids [] e = []"
  by (auto simp: added_ids_def map_filter_def)
    
lemma (in orset) [simp]:
  shows "added_ids (xs @ ys) e = added_ids xs e @ added_ids ys e"
    by (auto simp: added_ids_def map_filter_append)

lemma (in orset) added_ids_Broadcast_collapse [simp]:
  shows "added_ids ([Broadcast e]) e' = []"
  by (auto simp: added_ids_def map_filter_append map_filter_def)
    
lemma (in orset) added_ids_Deliver_Rem_collapse [simp]:
  shows "added_ids ([Deliver (i, Rem is e)]) e' = []"
  by (auto simp: added_ids_def map_filter_append map_filter_def)
    
lemma (in orset) added_ids_Deliver_Add_diff_collapse [simp]:
  shows "e \<noteq> e' \<Longrightarrow> added_ids ([Deliver (i, Add j e)]) e' = []"
  by (auto simp: added_ids_def map_filter_append map_filter_def)
  	
lemma (in orset) added_ids_Deliver_Append_diff_collapse [simp]:
  shows "e \<noteq> e' \<Longrightarrow> added_ids ([Deliver (i, Append e j)]) e' = []"
  by (auto simp: added_ids_def map_filter_append map_filter_def)
  	
lemma (in orset) added_ids_Deliver_Store_diff_collapse [simp]:
  shows "e \<noteq> e' \<Longrightarrow> added_ids ([Deliver (i, Store e mo j)]) e' = []"
  by (auto simp: added_ids_def map_filter_append map_filter_def)
    
lemma (in orset) added_ids_Deliver_Add_same_collapse [simp]:
  shows "added_ids ([Deliver (i, Add j e)]) e = [j]"
  by (auto simp: added_ids_def map_filter_append map_filter_def)
  	
lemma (in orset) added_ids_Deliver_Append_same_collapse [simp]:
  shows "added_ids ([Deliver (i, Append e j)]) e = [j]"
  by (auto simp: added_ids_def map_filter_append map_filter_def)
  	
lemma (in orset) added_ids_Deliver_Store_same_collapse [simp]:
  shows "added_ids ([Deliver (i, Store e mo j)]) e = [j]"
  by (auto simp: added_ids_def map_filter_append map_filter_def)

lemma (in orset) added_id_not_in_set:
  assumes "i1 \<notin> set (added_ids [Deliver (i, Add i2 e)] e)"
  shows "i1 \<noteq> i2"
  using assms by simp
  	
lemma (in orset) added_id_not_in_set2:
  assumes "i1 \<notin> set (added_ids [Deliver (i, Append e i2)] e)"
  shows "i1 \<noteq> i2"
  using assms by simp
  	
lemma (in orset) added_id_not_in_set3:
  assumes "i1 \<notin> set (added_ids [Deliver (i, Store e mo i2)] e)"
  shows "i1 \<noteq> i2"
  using assms by simp
 
  	
declare [[ smt_timeout = 120 ]]
	
lemma (in orset) apply_operations_added_ids:
  assumes "es prefix of j"
    and "apply_operations es = Some f"
  shows "(fst f) x \<subseteq> set (added_ids es x)"
using assms proof (induct es arbitrary: f rule: rev_induct, force)
  case (snoc x xs) thus ?case
  proof (cases x)
  	case (Broadcast x1)
  	then show ?thesis apply simp using snoc apply simp by blast
  next
  	case (Deliver e)
    moreover obtain a b where "e = (a, b)" by force
    ultimately show ?thesis 
      using snoc apply(case_tac b; clarsimp simp: interp_msg_def split: bind_splits)
      apply (simp add: op_elem_def interpret_op_def)
      	 apply (metis (no_types, lifting) added_id_not_in_set fst_conv fun_upd_other fun_upd_same insertE prefix_of_appendD subsetCE)
      	apply (smt Diff_iff fst_conv fun_upd_other fun_upd_same interpret_op_def operation.case(2) option.sel prefix_of_appendD subset_iff)
      unfolding interpret_op_def 
      apply (smt Un_iff added_ids_Deliver_Append_same_collapse fst_conv fun_upd_other fun_upd_same list.simps(15) op_elem_def operation.simps(19) option.inject prefix_of_appendD set_empty subset_iff)
      	
      	apply (simp add: added_id_not_in_set3 op_elem_def prefix_of_appendD subsetCE)
      	
      by (smt Diff_subset added_id_not_in_set3 fst_conv fun_upd_other fun_upd_same insertE subsetCE)
      	qed
  qed
    
lemma (in orset) Deliver_added_ids:
  assumes "xs prefix of j"
    and "i \<in> set (added_ids xs e)"
  shows "Deliver (i, Add i e) \<in> set xs \<or> Deliver (i, Append e i) \<in> set xs \<or> Deliver (i, Store e mo i) \<in> set xs"
using assms proof (induct xs rule: rev_induct, clarsimp)
  case (snoc x xs) thus ?case
  proof (cases x, force)
    case (Deliver e')
    moreover obtain a b where "e' = (a, b)" by force
    ultimately show ?thesis
      using snoc apply (case_tac b; clarsimp)
       apply (metis added_ids_Deliver_Add_diff_collapse added_ids_Deliver_Add_same_collapse
              empty_iff list.set(1) set_ConsD add_id_valid in_set_conv_decomp prefix_of_appendD)
       apply force
       using added_ids_Deliver_Append_diff_collapse added_ids_Deliver_Append_same_collapse append_id_valid
      	
      	 apply (metis (no_types, lifting) Diff_eq_empty_iff Diff_iff Un_iff list.set(1) list.set_intros(1) prefix_of_appendD set_ConsD set_append subset_Compl_singleton)
      
     proof -
     	 fix x41 x42 x43
     	 	 assume A1: "xs @ [Deliver (a, Store x41 x42 x43)] prefix of j"
       "i \<in> set (added_ids xs e) \<or> i \<in> set (added_ids [Deliver (a, Store x41 x42 x43)] e)"
       "b = Store x41 x42 x43 "
       "x = Deliver (a, Store x41 x42 x43) "
       "e' = (a, Store x41 x42 x43) "
       "(xs prefix of j \<Longrightarrow> i \<in> set (added_ids xs e) \<Longrightarrow> False) "
       "Deliver (i, Add i e) \<notin> set xs "
       "Deliver (i, Append e i) \<notin> set xs "
       "Deliver (i, Store e mo i) \<notin> set xs "   
       have A2: "a = x43" using A1 store_id_valid[of "xs @ [Deliver (a, Store x41 x42 x43)]" "j" "a" "x41" "x42" "x43"]
       	 by auto
       have "xs prefix of j" using A1 by auto
       show " i = a \<and> e = x41 \<and> mo = x42 \<and> i = x43" using A1 A2 added_ids_Deliver_Store_diff_collapse sorry
       	 	 	 
       	 		 qed
       (*done *) 
  qed
qed

lemma (in orset) Broadcast_Deliver_prefix_closed:
  assumes "xs @ [Broadcast (r, Rem ix e)] prefix of j"
    and "i \<in> ix"
  shows "Deliver (i, Add i e) \<in> set xs \<or> Deliver (i, Append e i) \<in> set xs \<or> Deliver (i, Store e mo i) \<in> set xs"
proof -  
  obtain y where "apply_operations xs = Some y"
    using assms broadcast_only_valid_msgs by blast
  moreover hence "ix = fst y e"
    by (metis (mono_tags, lifting) assms(1) broadcast_only_valid_msgs operation.case(2) option.simps(1)
     valid_behaviours_def case_prodD)
  ultimately show ?thesis
    using assms Deliver_added_ids apply_operations_added_ids by blast
qed

lemma (in orset) Broadcast_Deliver_prefix_closed2:
  assumes "xs prefix of j"
    and "Broadcast (r, Rem ix e) \<in> set xs"
    and "i \<in> ix"
  shows "Deliver (i, Add i e) \<in> set xs \<or> Deliver (i, Append e i) \<in> set xs \<or> Deliver (i, Store e mo i) \<in> set xs"
  using assms Broadcast_Deliver_prefix_closed by (induction xs rule: rev_induct; force)
  	
lemma (in orset) Broadcast_Deliver_prefix_closed3:
  assumes "xs @ [Broadcast (mn, Store e mo mn)] prefix of j"
    and "i = mo"
  shows "Deliver (i, Add i e) \<in> set xs \<or> Deliver (i, Append e i) \<in> set xs \<or> Deliver (i, Store e mo2 i) \<in> set xs"
proof - 
  obtain y where "apply_operations xs = Some y"
    using assms broadcast_only_valid_msgs by blast
  moreover hence "mo \<in> fst y e"
  	using broadcast_only_valid_msgs[of xs "(mn, Store e mo mn)" j] valid_behaviours_def [of y "(mn, Store e mo mn)"] 
  	using assms(1) by auto
  ultimately show ?thesis
    using assms Deliver_added_ids apply_operations_added_ids by blast
qed
	
lemma (in orset) Broadcast_Deliver_prefix_closed4:
  assumes "xs prefix of j"
    and "Broadcast (mn, Store e mo mn) \<in> set xs"
    and "i = mo"
  shows "Deliver (i, Add i e) \<in> set xs \<or> Deliver (i, Append e i) \<in> set xs \<or> Deliver (i, Store e mo2 i) \<in> set xs"
  using assms Broadcast_Deliver_prefix_closed3 by (induction xs rule: rev_induct; fastforce)
  	
lemma (in orset) ids_are_unique:
    assumes "xs prefix of j"
    and "(i, Add i e1) \<in> set (node_deliver_messages xs)" 
    and "(l, Append e2 l) \<in> set (node_deliver_messages xs)"
    and "(k, Store e3 mo k) \<in> set (node_deliver_messages xs)"
  shows "i \<noteq> k \<and> l \<noteq> k \<and> i \<noteq> l"
  	using assms delivery_has_a_cause events_before_exist prefix_msg_in_history
  	by (metis fst_conv msg_id_unique operation.distinct(11) operation.distinct(3) operation.distinct(5) prod.inject)
  		
lemma (in orset) append_prohibits_others:
    assumes "xs prefix of j"
    and "(i, Append e i) \<in> set (node_deliver_messages xs)"
    shows "(i, Store e mo i) \<notin> set (node_deliver_messages xs) \<and> (i, Add i e) \<notin> set (node_deliver_messages xs)" 
  	using assms delivery_has_a_cause events_before_exist prefix_msg_in_history
  	by (metis fst_conv msg_id_unique operation.distinct(11) operation.distinct(3) prod.inject)

lemma (in orset) concurrent_add_remove_independent_technical:
  assumes "i \<in> is"
    and "xs prefix of j"
    and "(i, Add i e) \<in> set (node_deliver_messages xs)" and "(ir, Rem is e) \<in> set (node_deliver_messages xs)"
  shows "hb (i, Add i e) (ir, Rem is e)"
proof -
  obtain pre k where "pre@[Broadcast (ir, Rem is e)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (i, Add i e) \<in> set pre \<or> Deliver (i, Append e i) \<in> set pre \<or> Deliver (i, Store e mo i) \<in> set pre"
    using Broadcast_Deliver_prefix_closed[of "pre" "ir" "is" "e" "k" "i" "mo"] assms(1) by auto
    	
  hence "Deliver (i, Add i e) \<in> set pre" using assms(2) assms(3) ids_are_unique[of "xs" j i e i e i e mo]
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD)
  ultimately show ?thesis
    using hb.intros(2) events_in_local_order by blast
qed
	
lemma (in orset) concurrent_append_remove_independent_technical:
  assumes "i \<in> is"
    and "xs prefix of j"
    and "(i, Append e i) \<in> set (node_deliver_messages xs)" and "(ir, Rem is e) \<in> set (node_deliver_messages xs)"
  shows "hb (i, Append e i) (ir, Rem is e)"
proof -
  obtain pre k where "pre@[Broadcast (ir, Rem is e)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (i, Add i e) \<in> set pre \<or> Deliver (i, Append e i) \<in> set pre \<or> Deliver (i, Store e mo i) \<in> set pre"
    using Broadcast_Deliver_prefix_closed[of "pre" "ir" "is" "e" "k" "i" "mo"] assms(1) by auto
    	
  hence "Deliver (i, Append e i) \<in> set pre" using assms(2) assms(3) ids_are_unique[of "xs" j i e i e i e mo]
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD)
  ultimately show ?thesis
    using hb.intros(2) events_in_local_order by blast
qed
	
lemma (in orset) concurrent_store_remove_independent_technical:
  assumes "mn \<in> is"
    and "xs prefix of j"
    and "(mn, Store e mo mn) \<in> set (node_deliver_messages xs)" and "(ir, Rem is e) \<in> set (node_deliver_messages xs)"
  shows "hb (mn, Store e mo mn) (ir, Rem is e)"
proof -
  obtain pre k where "pre@[Broadcast (ir, Rem is e)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (mn, Add mn e) \<in> set pre \<or> Deliver (mn, Append e mn) \<in> set pre \<or> Deliver (mn, Store e mo2 mn) \<in> set pre"
    using Broadcast_Deliver_prefix_closed[of "pre" "ir" "is" "e" "k" "mn" "mo2"] assms(1) by auto
    	
  hence "Deliver (mn, Store e mo mn) \<in> set pre" using assms(2) assms(3) ids_are_unique[of "xs" j mn e mn e mn e mo]
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD)
  ultimately show ?thesis
    using hb.intros(2) events_in_local_order by blast
qed
	
lemma (in orset) concurrent_add_store_independent_technical:
  assumes "i = mo"
    and "xs prefix of j"
    and "(i, Add i e) \<in> set (node_deliver_messages xs)" and "(mn, Store e mo mn) \<in> set (node_deliver_messages xs)"
  shows "hb (i, Add i e) (mn, Store e mo mn)"
proof -
  obtain pre k where "pre@[Broadcast (mn, Store e mo mn)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (i, Add i e) \<in> set pre \<or> Deliver (i, Append e i) \<in> set pre \<or> Deliver (i, Store e mo2 i) \<in> set pre"
    using Broadcast_Deliver_prefix_closed3[of pre mn e mo k i mo2] assms(1) by auto
    	
  hence "Deliver (i, Add i e) \<in> set pre" using assms(2) assms(3) ids_are_unique[of "xs" j i e i e i e mo]
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD)
  ultimately show ?thesis
    using hb.intros(2) events_in_local_order by blast
qed
	
lemma (in orset) concurrent_append_store_independent_technical:
  assumes "i = mo"
    and "xs prefix of j"
    and "(i, Append e i) \<in> set (node_deliver_messages xs)" and "(mn, Store e mo mn) \<in> set (node_deliver_messages xs)"
  shows "hb (i, Append e i) (mn, Store e mo mn)"
proof -
  obtain pre k where "pre@[Broadcast (mn, Store e mo mn)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (i, Add i e) \<in> set pre \<or> Deliver (i, Append e i) \<in> set pre \<or> Deliver (i, Store e mo2 i) \<in> set pre"
    using Broadcast_Deliver_prefix_closed3[of pre mn e mo k i mo2] assms(1) by auto
    	
  hence "Deliver (i, Append e i) \<in> set pre" using assms(2) assms(3) assms(1) 
  		ids_are_unique[of "xs" j i e i e i e mo] 
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD)
  ultimately show ?thesis
    using hb.intros(2) events_in_local_order by blast
qed
	
lemma (in orset) concurrent_store_store_independent_technical:
  assumes "mn1 = mo2"
    and "xs prefix of j"
    and "(mn1, Store e mo1 mn1) \<in> set (node_deliver_messages xs)" and "(mn2, Store e mo2 mn2) \<in> set (node_deliver_messages xs)"
  shows "hb (mn1, Store e mo1 mn1) (mn2, Store e mo2 mn2)"
proof -
  obtain pre k where "pre@[Broadcast (mn2, Store e mo2 mn2)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (mo2, Add mo2 e) \<in> set pre \<or> Deliver (mo2, Append e mo2) \<in> set pre \<or> Deliver (mo2, Store e mo1 mo2) \<in> set pre"
    using Broadcast_Deliver_prefix_closed3 assms(1) by auto    	
  hence "Deliver (mn1, Store e mo1 mn1) \<in> set pre" using assms(2) assms(3) assms(1) 
  		ids_are_unique 
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD)
  ultimately show ?thesis
    using hb.intros(2) events_in_local_order by blast
qed

lemma (in orset) Deliver_Add_same_id_same_message:
  assumes "Deliver (i, Add i e1) \<in> set (history j)" and "Deliver (i, Add i e2) \<in> set (history j)"
  shows "e1 = e2"
proof -
  obtain pre1 pre2 k1 k2 where *: "pre1@[Broadcast (i, Add i e1)] prefix of k1" "pre2@[Broadcast (i, Add i e2)] prefix of k2"
    using assms delivery_has_a_cause events_before_exist by meson
  moreover hence "Broadcast (i, Add i e1) \<in> set (history k1)" "Broadcast (i, Add i e2) \<in> set (history k2)"
    using node_histories.prefix_to_carriers node_histories_axioms by force+
  ultimately show ?thesis
    using msg_id_unique by fastforce
qed

lemma (in orset) ids_imply_messages_same:
  assumes "i \<in> is"
    and "xs prefix of j"
    and "(i, Add i e1) \<in> set (node_deliver_messages xs)" and "(ir, Rem is e2) \<in> set (node_deliver_messages xs)"
  shows "e1 = e2"
proof -
  obtain pre k where "pre@[Broadcast (ir, Rem is e2)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (i, Add i e2) \<in> set pre \<or> Deliver (i, Append e2 i) \<in> set pre \<or> Deliver (i, Store e2 mo i) \<in> set pre"
    using Broadcast_Deliver_prefix_closed assms(1) ids_are_unique by blast
  hence "Deliver (i, Add i e2) \<in> set pre" using assms(1) assms(2) assms(3)
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms operation.simps(10) operation.simps(8) prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD prod.simps(1))
  moreover have "Deliver (i, Add i e1) \<in> set (history j)"
    using assms(2) assms(3) prefix_msg_in_history by blast
  ultimately show ?thesis
    by (metis fst_conv msg_id_unique network.delivery_has_a_cause network_axioms operation.inject(1)
        prefix_elem_to_carriers prefix_of_appendD prod.inject)
qed
	
lemma (in orset) ids_imply_messages_same2:
  assumes "i = mo"
    and "xs prefix of j"
    and "(i, Add i e1) \<in> set (node_deliver_messages xs)" and "(mn, Store e2 mo mn) \<in> set (node_deliver_messages xs)"
  shows "e1 = e2"
proof -
  obtain pre k where "pre@[Broadcast (mn, Store e2 mo mn)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (i, Add i e2) \<in> set pre \<or> Deliver (i, Append e2 i) \<in> set pre \<or> Deliver (i, Store e2 mo2 i) \<in> set pre"
    using Broadcast_Deliver_prefix_closed3 assms(1) ids_are_unique by blast
  hence "Deliver (i, Add i e2) \<in> set pre" using assms(1) assms(2) assms(3)
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms operation.simps(10) operation.simps(8) prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD prod.simps(1))
  moreover have "Deliver (i, Add i e1) \<in> set (history j)"
    using assms(2) assms(3) prefix_msg_in_history by blast
  ultimately show ?thesis
    by (metis fst_conv msg_id_unique network.delivery_has_a_cause network_axioms operation.inject(1)
        prefix_elem_to_carriers prefix_of_appendD prod.inject)
qed
	
lemma (in orset) ids_imply_messages_same3:
  assumes "i = mo"
    and "xs prefix of j"
    and "(i, Append e1 i) \<in> set (node_deliver_messages xs)" and "(mn, Store e2 mo mn) \<in> set (node_deliver_messages xs)"
  shows "e1 = e2"
proof -
  obtain pre k where "pre@[Broadcast (mn, Store e2 mo mn)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (i, Add i e2) \<in> set pre \<or> Deliver (i, Append e2 i) \<in> set pre \<or> Deliver (i, Store e2 mo2 i) \<in> set pre"
    using Broadcast_Deliver_prefix_closed3 assms(1) ids_are_unique by blast
  hence "Deliver (i, Append e2 i) \<in> set pre" using assms(1) assms(2) assms(3)
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms operation.distinct(11) operation.distinct(3) prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD prod.inject)
  moreover have "Deliver (i, Append e1 i) \<in> set (history j)"
    using assms(2) assms(3) prefix_msg_in_history by blast
  ultimately show ?thesis 
  	by (smt added_ids_Deliver_Append_diff_collapse added_ids_Deliver_Append_same_collapse empty_iff fst_conv list.set(1) list.set_intros(1) network.delivery_has_a_cause network.msg_id_unique network_axioms prefix_elem_to_carriers prefix_of_appendD)
qed
		

lemma (in orset) ids_imply_messages_same4:
  assumes "mn1 = mo2"
    and "xs prefix of j"
    and "(mn1, Store e1 mo1 mn1) \<in> set (node_deliver_messages xs)" and "(mn2, Store e2 mo2 mn2) \<in> set (node_deliver_messages xs)"
  shows "e1 = e2"
proof -
  obtain pre k where "pre@[Broadcast (mn2, Store e2 mo2 mn2)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  moreover hence "Deliver (mo2, Add mo2 e2) \<in> set pre \<or> Deliver (mo2, Append e2 mo2) \<in> set pre \<or> Deliver (mo2, Store e2 mo1 mo2) \<in> set pre"
    using Broadcast_Deliver_prefix_closed3 assms(1) ids_are_unique by blast
  hence "Deliver (mo2, Store e2 mo1 mo2) \<in> set pre" using assms(1) assms(2) assms(3) 
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms operation.distinct(11) operation.distinct(5) prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD prod.inject)
  moreover have "Deliver (mn1, Store e1 mo1 mn1) \<in> set (history j)"
    using assms(2) assms(3) prefix_msg_in_history by blast
  ultimately show ?thesis
  	by (metis (no_types, lifting) assms(1) fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms operation.inject(4) prefix_elem_to_carriers prefix_of_appendD prod.inject)
qed
	
lemma (in orset) ids_imply_messages_same5:
  assumes "i \<in> is"
    and "xs prefix of j"
    and "(i, Append e1 i) \<in> set (node_deliver_messages xs)" and "(ir, Rem is e2) \<in> set (node_deliver_messages xs)"
  shows "e1 = e2"
proof -
  obtain pre k where "pre@[Broadcast (ir, Rem is e2)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  
   moreover hence "Deliver (i, Add i e2) \<in> set pre \<or> Deliver (i, Append e2 i) \<in> set pre \<or> Deliver (i, Store e2 mo2 i) \<in> set pre"
    using Broadcast_Deliver_prefix_closed3 assms(1)
    by (meson orset.Broadcast_Deliver_prefix_closed orset_axioms)
    	
  hence "Deliver (i, Append e2 i) \<in> set pre" using assms(2) assms(3) assms(1) 
  by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms operation.distinct(11) operation.simps(8) prefix_elem_to_carriers prefix_msg_in_history prefix_of_appendD prod.simps(1))

  	moreover have "Deliver (i, Append e1 i) \<in> set (history j)"
    using assms(2) assms(3) prefix_msg_in_history by blast
  ultimately show ?thesis
    by (metis (no_types, lifting) fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms operation.inject(3) prefix_elem_to_carriers prefix_of_appendD prod.inject)
qed
	
lemma (in orset) ids_imply_messages_same6:
  assumes "mn1 \<in> is"
    and "xs prefix of j"
    and "(mn1, Store e1 mo1 mn1) \<in> set (node_deliver_messages xs)" and "(ir, Rem is e2) \<in> set (node_deliver_messages xs)"
  shows "e1 = e2"
proof -
  obtain pre k where "pre@[Broadcast (ir, Rem is e2)] prefix of k"
    using assms delivery_has_a_cause events_before_exist prefix_msg_in_history by blast
  
   moreover hence "Deliver (mn1, Add mn1 e2) \<in> set pre \<or> Deliver (mn1, Append e2 mn1) \<in> set pre \<or> Deliver (mn1, Store e2 mo1 mn1) \<in> set pre"
    using Broadcast_Deliver_prefix_closed3 assms(1)
    by (meson orset.Broadcast_Deliver_prefix_closed orset_axioms)
    	
  hence "Deliver (mn1, Store e2 mo1 mn1) \<in> set pre" using assms(2) assms(3) assms(1)
  	by (smt calculation fst_conv network.delivery_has_a_cause network.msg_id_unique network.prefix_msg_in_history network_axioms operation.distinct(11) operation.simps(10) prefix_elem_to_carriers prefix_of_appendD prod.inject)

  	moreover have "Deliver (mn1, Store e1 mo1 mn1) \<in> set (history j)"
    using assms(2) assms(3) prefix_msg_in_history
    by (smt calculation(1) calculation(2) fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms operation.inject(4) prefix_elem_to_carriers prefix_of_appendD prod.inject)
  ultimately show ?thesis
  	by (metis (full_types) fst_conv network.delivery_has_a_cause network.msg_id_unique network_axioms operation.inject(4) prefix_elem_to_carriers prefix_of_appendD prod.inject)
qed

corollary (in orset) concurrent_add_remove_independent:
  assumes "\<not> hb (i, Add i e1) (ir, Rem is e2)" and "\<not> hb (ir, Rem is e2) (i, Add i e1)"
    and "xs prefix of j"
    and "(i, Add i e1) \<in> set (node_deliver_messages xs)" and "(ir, Rem is e2) \<in> set (node_deliver_messages xs)"
  shows "i \<notin> is"
  using assms ids_imply_messages_same concurrent_add_remove_independent_technical by fastforce
  	
corollary (in orset) concurrent_add_store_independent:
  assumes "\<not> hb (i, Add i e1) (mn, Store e2 mo mn)" and "\<not> hb (mn, Store e2 mo mn) (i, Add i e1)"
    and "xs prefix of j"
    and "(i, Add i e1) \<in> set (node_deliver_messages xs)" and "(mn, Store e2 mo mn) \<in> set (node_deliver_messages xs)"
  shows "i \<noteq> mo"
  using assms ids_imply_messages_same2 concurrent_add_store_independent_technical by fastforce
  	
corollary (in orset) concurrent_append_store_independent:
  assumes "\<not> hb (m, Append e1 m) (mn, Store e2 mo mn)" and "\<not> hb (mn, Store e2 mo mn) (m, Append e1 m)"
    and "xs prefix of j"
    and "(m, Append e1 m) \<in> set (node_deliver_messages xs)" and "(mn, Store e2 mo mn) \<in> set (node_deliver_messages xs)"
  shows "m \<noteq> mo"
  using assms ids_imply_messages_same3 concurrent_append_store_independent_technical by fastforce
  	
corollary (in orset) concurrent_store_store_independent:
  assumes "\<not> hb (mn1, Store e1 mo1 mn1) (mn2, Store e2 mo2 mn2)" and "\<not> hb (mn2, Store e2 mo2 mn2) (mn1, Store e1 mo1 mn1)"
    and "xs prefix of j"
    and "(mn1, Store e1 mo1 mn1) \<in> set (node_deliver_messages xs)" and "(mn2, Store e2 mo2 mn2) \<in> set (node_deliver_messages xs)"
  shows "mn1 \<noteq> mo2 \<and> mn2 \<noteq> mo1"
  using assms ids_imply_messages_same4 concurrent_store_store_independent_technical by metis
  	
corollary (in orset) concurrent_append_remove_independent:
  assumes "\<not> hb (i, Append e1 i) (ir, Rem is e2)" and "\<not> hb (ir, Rem is e2) (i, Append e1 i)"
    and "xs prefix of j"
    and "(i, Append e1 i) \<in> set (node_deliver_messages xs)" and "(ir, Rem is e2) \<in> set (node_deliver_messages xs)"
  shows "i \<notin> is"
  using assms ids_imply_messages_same5 concurrent_append_remove_independent_technical by fastforce
  	
corollary (in orset) concurrent_store_remove_independent:
  assumes "\<not> hb (mn1, Store e1 mo1 mn1) (ir, Rem is e2)" and "\<not> hb (ir, Rem is e2) (i, Append e1 i)"
    and "xs prefix of j"
    and "(mn1, Store e1 mo1 mn1) \<in> set (node_deliver_messages xs)" and "(ir, Rem is e2) \<in> set (node_deliver_messages xs)"
  shows "mn1 \<notin> is"
  using assms ids_imply_messages_same6 concurrent_store_remove_independent_technical by fastforce
 

	
lemma (in orset) concurrent_operations_commute2:
  assumes "xs prefix of i"
  shows "hb.concurrent_ops_commute (node_deliver_messages xs)"                     
proof -
  { fix a b x y
    assume "(a, b) \<in> set (node_deliver_messages xs)"
           "(x, y) \<in> set (node_deliver_messages xs)"
           "hb.concurrent (a, b) (x, y)"
    hence "interp_msg (a, b) \<rhd> interp_msg (x, y) = interp_msg (x, y) \<rhd> interp_msg (a, b)"
      apply(unfold interp_msg_def, case_tac "b"; case_tac "y"; simp add: add_add_commute rem_rem_commute hb.concurrent_def)
       apply (metis add_id_valid add_rem_commute assms concurrent_add_remove_independent hb.concurrentD1 hb.concurrentD2 prefix_contains_msg)+
      done
  } thus ?thesis
    by(fastforce simp: hb.concurrent_ops_commute_def)
qed
  	
lemma (in orset) concurrent_operations_commute:
  assumes "xs prefix of i"
  shows "hb.concurrent_ops_commute (node_deliver_messages xs)"                       	
proof -
	
  { fix a b x y
    assume A1: "(a, b) \<in> set (node_deliver_messages xs)"
           "(x, y) \<in> set (node_deliver_messages xs)"
           "hb.concurrent (a, b) (x, y)"
    hence "interp_msg (a, b) \<rhd> interp_msg (x, y) = interp_msg (x, y) \<rhd> interp_msg (a, b)" sorry




      
  } thus ?thesis
    by(fastforce simp: hb.concurrent_ops_commute_def)
qed
  

theorem (in orset) convergence:
  assumes "set (node_deliver_messages xs) = set (node_deliver_messages ys)"
      and "xs prefix of i" and "ys prefix of j"
    shows "apply_operations xs = apply_operations ys"
using assms by(auto simp add: apply_operations_def intro: hb.convergence_ext concurrent_operations_commute
                node_deliver_messages_distinct hb_consistent_prefix)
              
context orset begin

sublocale sec: strong_eventual_consistency weak_hb hb interp_msg
  "\<lambda>ops.\<exists>xs i. xs prefix of i \<and> node_deliver_messages xs = ops" "(\<lambda>x.{}, \<lambda> x. None)"
  apply(standard; clarsimp simp add: hb_consistent_prefix node_deliver_messages_distinct
        concurrent_operations_commute)
  unfolding hb.apply_operations_def node_deliver_messages_def interp_msg_def apply simp
    apply (meson interpret_op_def)
    by (metis drop_last_message trivial_network.node_deliver_messages_def)
end
end

  