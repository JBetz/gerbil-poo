;;-*- Gerbil -*-
;; Trivial implementation of Prototype Object Orientation in Gerbil Scheme.
;;
;; See doc/poo.md for documentation
;; TODO: see Future Features and the Internals TODO sections in document above.

(export #t);; XXX for debugging macros as used in other modules; remove afterwards
(export
  .o .o/ctx .def .def/ctx
  poo? .mix .ref .instantiate .get .call .def! .key? .has?
  .putslot! .setslot! .put! .set!
  .all-slots .all-slots-sorted .alist .sorted-alist .<-alist
  .@ .+ .cc
  poo poo-prototypes poo-instance ;; shouldn't these remain internals?
  with-slots)

(import
  ;;(for-syntax :std/misc/repr) :std/misc/repr ;; XXX debug
  :std/lazy :std/misc/hash :std/misc/list :std/sort :std/srfi/1 :std/srfi/13 :std/sugar
  (for-syntax :clan/base :std/iter)
  :clan/base)

(defstruct poo (prototypes instance) constructor: :init!)
(defmethod {:init! poo}
   (lambda (self prototypes (instance #f))
     (struct-instance-init! self prototypes instance)))

(def (.instantiate poo.)
  (match poo.
    ((poo _ #f) (set! (poo-instance poo.) (hash))) ;; TODO: call .init method?
    ((poo _ _) (void)) ;; already instantiated
    (else (error "No poo" poo.))))

(def (no-such-slot poo. slot)
  (λ () (error "No such slot" poo. slot)))

(def (.ref poo. slot (base (no-such-slot poo. slot)))
  (try
    (begin
      (.instantiate poo.)
      (match poo.
        ((poo prototypes instance)
        (hash-ensure-ref instance slot (cut compute-slot poo. prototypes slot base)))))
    (catch (err)
      (error (error-message err) slot))))

(def (compute-slot poo. prototypes slot base)
  (match prototypes
    ([] (base))
    ([prototype . super-prototypes]
     (if-let (fun (hash-get prototype slot))
        (fun poo. super-prototypes base)
        (compute-slot poo. super-prototypes slot base)))))

(def (append-prototypes x (prototypes []))
  (match x ;; TODO: use lazy merging of patricia trees to maximize the sharing of structure? hash-consing?
    ([] prototypes)
    ((cons x y) (append-prototypes x (append-prototypes y prototypes)))
    ((poo ps _) (append ps prototypes))
    (_ (error "invalid poo spec" x))))

(def (.mix . poos)
  (poo (append-prototypes poos) #f))

(def (.+ base . mixins)
  (.mix mixins base))

(def (.key? poo. slot)
  (match poo.
    ((poo prototypes instance)
     (or (and instance (hash-key? instance slot)) ;; fast check for already-computed slot, also includes slots from .put! or .set!
         (any (cut hash-key? <> slot) prototypes)))
    (else (error ".key?: not poo" poo. slot))))

(defrules .has? ()
  ((_ x) #t)
  ((_ x slot) (.key? x 'slot))
  ((_ x slot1 slot2 slot3 ...) (and (.has? x slot1) (.has? x slot2 slot3 ...))))

(def .all-slots
  (nest
   (λ-ematch) ((poo prototypes instance))
   (with-list-builder (c))
   (let (h (if instance (hash-copy instance) (hash)))
     (when instance (for-each! (hash-keys instance) c)))
   (for-each! prototypes) (λ (p))
   ((cut hash-for-each <> p)) (λ (k _))
   (unless (hash-key? h k)
     (hash-put! h k #t)
     (c k))))

(def (.all-slots-sorted poo)
  (sort (.all-slots poo) symbol<?))

(def (.alist poo)
  (map (λ (slot) (cons slot (.ref poo slot))) (.all-slots poo)))

(def (.sorted-alist poo)
  (map (λ (slot) (cons slot (.ref poo slot))) (.all-slots-sorted poo)))

;; For (? test :: proc => pattern),
;;   test = (o?/keys ks)
;;   proc = (.refs/keys ks)
(def ((o?/keys ks) o) (and (poo? o) (andmap (cut .key? o <>) ks)))
(def ((.refs/keys ks) o) (map (cut .ref o <>) ks))

;; the ctx argument exists for macro-scope purposes
;; TODO: use a syntax-parameter for self instead of the ctx argument?
(defrules .o/ctx ()
  ((_ ctx (:: self) slot-spec ...)
   (poo/slots ctx self [] () slot-spec ...))
  ((_ ctx (:: self super slots ...) slot-spec ...)
   (poo/slots ctx self super (slots ...) slot-spec ...))
  ((_ ctx () slot-spec ...)
   (poo/slots ctx self [] () slot-spec ...))
  ((_ ctx slot-spec ...)
   (poo/slots ctx self [] () slot-spec ...)))

(begin-syntax
  ;; TODO: is there a better option than (stx-car stx) to introduce correct identifier scope?
  ;; the stx argument is the original syntax #'(.o args ...) or #'(@method args ...)
  (def (unkeywordify-syntax ctx k)
    (!> k
        syntax->datum
        keyword->string
        string->symbol
        (cut datum->syntax (stx-car ctx) <>)))

  ;; A NormalizedSlotSpec is one of:
  ;;  - (slot-name value-expr)                           ; ignore parent, override
  ;;  - (slot-name => function-expr extra-arg-expr ...)  ; invoke parent, pass into function
  ;;  - (slot-name (inherited-computation) value-expr)   ; lazy reference to parent
  ;;  - (slot-name)                                      ; same-named var from surrounding scope
  ;;  - (slot-name =>.+ poo-expr)                        ; combine parent with a mixin
  ;; Interpretation according to `doc/poo.md` section `POO Definition Syntax`

  (def (normalize-named-slot-specs ctx name specs)
    (syntax-case specs (=> =>.+)
      ((=> value-spec . more)
       (with-syntax ((name name))
         (cons #'(name => value-spec) (normalize-slot-specs ctx #'more))))
      ((=>.+ value-spec . more)
       (with-syntax ((name name))
         (cons #'(name =>.+ value-spec) (normalize-slot-specs ctx #'more))))
      ((value-spec . more)
       (with-syntax ((name name))
         (cons #'(name value-spec) (normalize-slot-specs ctx #'more))))
      (() (error "missing value after slot name" name (syntax->datum name) ctx (syntax->datum ctx)))))

  (def (normalize-slot-specs ctx specs)
    (syntax-case specs ()
      (() '())
      ((arg . more)
       (let ((e (syntax-e #'arg)))
         (cond
          ((pair? e)
           (cons #'arg (normalize-slot-specs ctx #'more)))
          ((symbol? e)
           (cons #'(arg) (normalize-slot-specs ctx #'more)))
          ((keyword? e)
           (normalize-named-slot-specs ctx (unkeywordify-syntax ctx #'arg) #'more))
          (else
           (error "bad slot spec" #'arg)))))))

  (def (normalize-slot-specs-for-match ctx specs)
    (for/collect ((s (normalize-slot-specs ctx specs)))
      (syntax-case s (=> =>.+)
        ((slot form) #'(slot form))
        ((slot) #'(slot slot))
        ((slot => . _) (raise-syntax-error #f "=> not allowed in patterns" ctx))
        ((slot =>.+ . _) (raise-syntax-error #f "=>.+ not allowed in patterns" ctx))
        ((slot (next-method) form) (raise-syntax-error #f "(inherited-computation) not allowed in patterns" ctx))))))

;; the ctx argument exists for macro-scope purposes
(defsyntax (poo/slots stx)
  (syntax-case stx ()
    ((_ ctx self super (slots ...) . slot-specs)
     (with-syntax ((((slot spec ...) ...) (normalize-slot-specs #'ctx #'slot-specs)))
       #'(poo/init self super (slots ... slot ...) (slot spec ...) ...)))))

(defrules poo/init ()
  ((_ self super slots (slot slotspec ...) ...)
   (poo (cons (hash (slot (poo/slot-init-form self slots slot slotspec ...)) ...)
              (append-prototypes super)) #f)))

(defrules poo/form-named (lambda λ)
  ((_ slot (lambda formals body ...)) (fun (slot . formals) body ...)) ;; L A M B D A
  ((_ slot (λ formals body ...)) (fun (slot . formals) body ...)) ;; unicode Λ
  ((_ slot form) form))

(defrules poo/slot-init-form (=> =>.+)
  ((_ self slots slot form)
   (λ (self super-prototypes base)
     (with-slots (self . slots) (poo/form-named slot form))))
  ((_ self slots slot => form args ...)
   (λ (self super-prototypes base)
     (let ((inherited-value (compute-slot self super-prototypes 'slot base)))
       (with-slots (self . slots) (form inherited-value args ...)))))
  ((_ self slots slot =>.+ args ...)
   (poo/slot-init-form self slots slot => .+ args ...))
  ((_ self slots slot (next-method) form)
   (λ (self super-prototypes base)
     (let ((inherited-value (lazy (compute-slot self super-prototypes 'slot base))))
       (let-syntax ((next-method (syntax-rules () ((_) (force inherited-value)))))
         (with-slots (self . slots) (poo/form-named slot form))))))
  ((_ self slots slot)
   (λ (self super-prototypes base) slot)))

;;NB: This doesn't work, because of slots that appear more than once.
#;(defrule (with-slots (self slot ...) body ...) (let-id-rule ((slot (.@ self slot)) ...) body ...))

(defrules with-slots ()
  ((_ (self) body ...) (begin body ...))
  ((_ (self slot slots ...) body ...)
   (let-id-rule (slot (.@ self slot)) (with-slots (self slots ...) body ...))))

;; TODO: use defsyntax-for-match, and in the pattern use (? test :: proc => pattern) to do the job
(defsyntax-for-match .o
  (lambda (stx)
    (syntax-case stx ()
      ((_ args ...)
       (with-syntax ((((k v) ...) (normalize-slot-specs-for-match stx #'(args ...))))
        #'(? (o?/keys '(k ...)) :: (.refs/keys '(k ...)) => [v ...])))))
  (lambda (stx)
    (syntax-case stx ()
      ((_ args ...)
       (with-syntax ((ctx stx)) #'(.o/ctx ctx args ...))))))

(defsyntax (.def stx)
  (syntax-case stx ()
    ((_ args ...)
     (with-syntax ((ctx stx)) #'(.def/ctx ctx args ...)))))

;; the ctx argument exists for macro-scope purposes
(defrules .def/ctx ()
  ((_ ctx (name options ...) slot-defs ...)
   (def name (.o/ctx ctx (:: options ...) slot-defs ...)))
  ((_ ctx name slot-defs ...)
   (def name (.o/ctx ctx () slot-defs ...))))

(defrules .get ()
  ((_ poo) poo)
  ((_ poo slot slots ...) (.get (.ref poo 'slot) slots ...)))

(defalias .@ .get)

(defrules .call ()
  ((_ poo slot args ...) ((.get poo slot) args ...)))

(def (.putslot! poo. slot definition)
  (ematch poo. ((poo [proto . protos] _) (hash-put! proto slot definition))))

(defrules .setslot! () ((_ poo. slot value) (.putslot! poo. 'slot value)))

(defrules .def! () ;; TODO: check prototype mutability status first
  ((_ poo slot (slots ...) slotspec ...)
   (.putslot! poo 'slot (poo/slot-init-form poo (slot slots ...) slot slotspec ...))))

(def (.put! poo. slot value) ;; TODO: check instance mutability status first
  (try
    (begin
      (.instantiate poo.)
      (hash-put! (poo-instance poo.) slot value))
    (catch (err)
      (error (error-message err) slot))))

(defrules .set! () ((_ poo. slot value) (.put! poo. 'slot value)))

(def (.<-alist alist)
  (def o (.o))
  (for-each (match <> ([k . v] (.putslot! o k (λ (self super-prototypes base) v)))) alist)
  o)

;; carbon copy / clone c...
(def (.cc poo. . overrides)
  (def i (cond ((poo-instance poo.) => hash-copy) (else (hash))))
  (def o (poo (poo-prototypes poo.) i))
  (let loop ((l overrides))
    (match l
      ([] (void))
      ([(? symbol? s) v . r] (hash-put! i s v) (loop r))
      ([(? keyword? k) v . r] (hash-put! i (string->symbol (keyword->string k)) v) (loop r))
      (else (error "invalid poo overrides" overrides))))
  o)
;; TODO: a syntax that allows for => / =>.+ overrides as well as setting values.
;; TODO: find an efficient way to repeatedly override one field in a pure way without leaking memory,
;; in O(log n) rather than O(n)?
;; TODO: maybe have explicitly distinct variants of stateful vs pure poo?
;; Could one convert from the other, with some freezing and thawing or copying operations?
;; When overriding a field, should we invalidate all the cached values for all fields?
;; Should we keep an indefinitely growing list of the super formulas?
;; Should we maintain flags as to which formulas do or don't use the super and/or self references,
;; so we know what to invalidate or not?
