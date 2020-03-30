From mathcomp   Require Import ssreflect ssrnat ssrbool ssrfun eqtype seq.
From QuickChick Require Import QuickChick.
From compcert   Require Import Integers IEEE754_extra.
From Hammer     Require Import Hammer Reconstr.
From Coq        Require Import ZArith.

Set Implicit Arguments.            Unset Strict Implicit.
Unset Printing Implicit Defensive. Set Bullet Behavior "None".

Module opt.
Fixpoint lift X Y Z (f:X->Y->Z) a b : option Z :=
  match a,b with | Some a,Some b => Some(f a b)
                 | _,_ => None
  end.

Definition map := option_map.
End opt.


Module seqx.
Definition zipWith A B C (f: A->B->C) :=
  fix zipWith (s: seq A) (t: seq B) {struct s}: seq C :=
    match s, t with
    | [::],_ | _,[::] => [::]
    | x::s, y::t => f x y :: zipWith s t
    end.

Definition seqOpt X (a:seq(option X)) : option(seq X) :=
  foldr (opt.lift cons) (Some[::]) a.
End seqx.


Module NE. Section NE.
Variables A B C : Type.
Inductive ne A := mk of A & seq A.

Definition sing (a:A) := mk a [::].

Definition map (f:A->B) (s:ne A):=
  let 'mk a aa:=s in mk (f a) (seq.map f aa).

Definition rev (s:ne A): ne A :=
  let 'mk a bb:=s in let r:=rcons(rev bb)a in mk(last a bb)(behead r).

Definition head '(mk a _) := a:A.

Definition tolist '(mk a aa) := a::aa : seq A.

Definition seqOpt X (a:ne(option X)) : option(ne X) :=
  match a with NE.mk None _ => None
             | NE.mk (Some a) aa => if seqx.seqOpt aa is Some r
                                    then Some(NE.mk a r) else None
  end.

Definition zipWith (f:A->B->C) (a:ne A) (b:ne B): ne C :=
  let '(mk a aa, mk b bb) := (a,b) in mk (f a b) (seqx.zipWith f aa bb).


Remark wtf_last (a:A)(aa:seq A) :
  last(last a aa)(behead(rcons(seq.rev aa)a)) = a.
Proof.
rewrite -(revK aa); set r:=seq.rev aa; rewrite revK.
by case: r=> //= r rr; rewrite rev_cons last_rcons.
Qed.

Remark wtf_behead (a:A)(aa:seq A) :
  behead(rcons(seq.rev(behead(rcons(seq.rev aa)a))) (last a aa)) = aa.
Proof.
rewrite -(revK aa); set r:=seq.rev aa; rewrite revK.
case: r=> //= r rr. by rewrite rev_cons last_rcons rev_rcons rcons_cons.
Qed.

Lemma revK (a:ne A): rev(rev a) = a.
Proof.
case: a=> //a l. by rewrite /rev wtf_last wtf_behead.
Qed.
End NE. End NE.
Notation seq1:=NE.ne.


Module   I32:=Int.     Module   I64:=Int64.
Notation i32:=I32.int. Notation i64:=I64.int.
Notation "[i32 i m ]" := (I32.mkint i m)(format "[i32  i  m ]").
Notation "[i64 i m ]" := (I64.mkint i m)(format "[i64  i  m ]").


Inductive Nu := I of i32 | J of i64.
Inductive At := ANu of Nu.
Inductive Ty := Ti|Tj|TL.
Inductive K :=
| A of At
| L of Ty & nat & seq1 K.

Section arith.
Definition ONi := I(I32.repr I32.min_signed).
Definition ONj := J(I64.repr I64.min_signed).
Definition Oi := I I32.zero.
Definition Oj := J I64.zero.

Definition Kiofnat (n:nat):K := A(ANu(I(I32.repr(Z.of_nat n)))).
Definition Kjofnat (n:nat):K := A(ANu(J(I64.repr(Z.of_nat n)))).

Definition iwiden (a:i32):i64 := I64.repr(I32.signed a).

Definition addnu (a b:Nu) := match a,b with
  | I i, I j => I(I32.add i j)
  | J i, J j => J(I64.add i j)
  | I i, J j => J(I64.add (iwiden i)j)
  | J i, I j => J(I64.add i(iwiden j)) end.

Definition K2j := Kjofnat 2.

Definition eqnu (a b:Nu) := match a,b with
  | I i, I j => I32.eq i j
  | J i, J j => I64.eq i j
  | I i, J j => I64.eq (iwiden i)j
  | J i, I j => I64.eq i(iwiden j)
end.

Lemma wide_range a: (I64.min_signed <= I32.signed a <= I64.max_signed)%Z.
Admitted.


Lemma addnuC a b : addnu a b = addnu b a.
Proof.
elim a=>i; elim b=>j => /=.
- by rewrite I32.add_commut.
- rewrite/iwiden !I64.add_signed I64.signed_repr;
    [rewrite Z.add_comm//| exact: wide_range].
- rewrite/iwiden !I64.add_signed I64.signed_repr;
    [rewrite Z.add_comm//| exact: wide_range].
by rewrite I64.add_commut.
Qed.

Lemma addnu0i a : addnu a Oi = a.
Proof.
elim a=>i /=. by rewrite I32.add_zero.
by rewrite/iwiden I32.signed_zero I64.add_zero.
Qed.

Lemma addnu0j a : eqnu (addnu a Oj) a.
Proof.
elim a=>i /=.
- by rewrite/iwiden I64.add_zero I64.eq_true.
by rewrite I64.add_zero I64.eq_true.
Qed.
End arith.



Definition K0j := A(ANu Oj).  Definition K1j := A(ANu(J I64.one)).
Definition K0i := A(ANu Oi).  Definition K1i := A(ANu(I I32.one)).

Definition K00i := L Ti 0 (NE.mk K0i  [::]).
Definition K31i := L Ti 3 (NE.mk K1i  [::K1i;K1i]).
Definition K331i:= L TL 3 (NE.mk K31i [::K31i;K31i]).





Section ops.


Fixpoint map_a1 (f:At->At) (x:K): K :=
  match x with
  | A n => A (f n)
  | L t n aa => L t n (NE.map (map_a1 f) aa)
  end.

Fixpoint thread_a1 (f:At->At->At) (a b: K) {struct a}: K :=
  match a, b with
  | A a, A b     => A (f a b)
  | L _ _ _, A b => map_a1 (f^~b) a
  | A a, L _ _ _ => map_a1 (f a) b
  | L ta na a, L tb nb b => L ta na (NE.zipWith (thread_a1 f) a b)
  end.


Fixpoint map_a (f:At->option At) (x:K): option K :=
  match x with
  | A n => option_map A (f n)
  | L t n aa => option_map (L t n) (NE.seqOpt (NE.map (map_a f) aa))
  end.

Fixpoint thread_a (f:At->At->option At) (a b: K) {struct a}: option K :=
  match a, b with
  | A a, A b     => option_map A (f a b)
  | L _ _ _, A b => map_a (f^~b) a
  | A a, L _ _ _ => map_a (f a) b
  | L ta na a, L tb nb b =>
    option_map (L ta na) (NE.seqOpt (NE.zipWith (thread_a f) a b))
  end.

Definition addi (a b:At): option At :=
  match a,b with ANu a,ANu b => Some(ANu(addnu a b)) end.



Definition ktype (a:K):Ty := match a with
| A(ANu(I _))=>Ti | A(ANu(J _))=>Tj | L _ _ _=> TL
end.


Definition ksize (a:K):K := match a with
| A a => K1i | L _ n _ => Kiofnat n
end.

Notation "#:" := (ksize)(at level 10).




Fixpoint nullify a := match a with
| A(ANu(I _))=> A(ANu Oi)
| A(ANu(J _))=> A(ANu Oj)
| L t n aa   => L t n (NE.map nullify aa)
end.


(* Definition unil:K := L TL 0 _ [::]. *)

Definition khead (k:K):K := match k with
| A _=> k | L t 0 a=> nullify (NE.head a) | L t n a=> NE.head a
end.

Notation "*:" := (khead)(at level 10).

Definition krev (k:K):K := match k with
| A _=> k | L t 0 a=> k | L t n aa=> L t n (NE.rev aa)
end.

Notation "|:" := (krev)(at level 10).





Lemma krevK : involutive (|:).
Proof.
case=> t // n aa. case: n=> //= n. by rewrite NE.revK.
Qed.

Lemma size_krev a : #:(|:a) = #:a.
Proof. case: a=> // t n aa. case: n=> //. Qed.


Definition enlist (a:K):K := L TL 1 (NE.sing a).

Notation ",:" := (enlist)(at level 10).

Lemma size_enlist a : #:(,:a) = K1i.  Proof. by[]. Qed.



Definition krconst (a b:K):K := b.
Notation "::" := (krconst)(at level 10).


Definition izero := I32.eq I32.zero.
Definition ipos := I32.lt I32.zero.  Definition ineg := I32.lt^~I32.zero.

Definition isI a := if a is A(ANu(I _)) then true else false.
Definition isIpos a := if a is A(ANu(I n)) then ipos n else false.


Definition kiota (a:K):option K := match a with
  | A(ANu(I ni))=>
    if izero ni then
      Some(L Ti 0 (NE.sing K0i))
    else if ipos ni then
      let n:=Z.to_nat (I32.signed ni)
      in Some(L Ti n (NE.mk K0i [seq Kiofnat i|i<-iota 1 n.-1]))
    else None
  | _=> None
end.


Notation "!:" := (kiota)(at level 10).




Lemma i_dec (a:i32) : {a=I32.zero}
                    + {izero a=false /\ ipos a /\ ineg a=false}
                    + {izero a=false /\ ipos a=false /\ ineg a}.
Admitted.



Lemma size_kiota a : isIpos a -> option_map (#:)(!:a) = Some a.
Proof.
case: a=> //= a. case: a => // n. case: n=> //i POS.
case: (i_dec i). case.
- scrush.
- case=> ->[] -> _ /=. rewrite/Kiofnat Z2Nat.id.
  + by rewrite Int.repr_signed.
  move:POS. rewrite/ipos.
  ryreconstr (@Z.lt_le_incl, @I32.signed_zero) (@is_true, @I32.lt).
scrush.
Qed.


(* Definition kfold (a f:K):K := match a with *)
(*   | A a=> a | L _ _ a aa=> foldl  *)


End ops.
