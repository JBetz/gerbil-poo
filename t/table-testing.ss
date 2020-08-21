(export #t)

(import
  :gerbil/gambit/bits :gerbil/gambit/random :gerbil/gambit/ports
  :std/format :std/iter :std/misc/list :std/misc/queue
  :std/sort :std/srfi/1 :std/srfi/13 :std/sugar :std/test
  :clan/assert :clan/base :clan/debug :clan/hash :clan/list :clan/number :clan/option :clan/roman
  :clan/with-id
  :clan/t/test-support
  ../poo ../mop ../io ../number ../type ../fun ../table ../rationaldict)

;; TODO: systematically write function properties and make more property-based tests?
;; TODO: support multimethods / externally defined methods / monkey patching / whatever
;;  so that tests can be defined as generic functions?

(defsyntax (def-table-test-accessors stx)
  (syntax-case stx ()
    ((ctx T) #'(ctx ctx T))
    ((_ ctx T)
     #'(with-id ctx (E F alist<- <-alist)
         (defrule (E e) (.@ T e))
         (defrule (F f args (... ...)) (.call T f args (... ...)))
         ;; TODO: for tries, check that the alists are already sorted!
         (def (alist<- t) (sort (F .list<- (validate T t)) (comparing-key test: < key: car)))
         (def (<-alist t) (validate T (F .<-list (shuffle-list t))))))))

(defrule (table-test-case T name body ...)
  (test-case (format "~a for ~s" name (.@ T sexp))
    (def-table-test-accessors T T)
    body ...))

(def (sort-alist alist) (sort alist (comparing-key test: < key: car)))
(def (shuffle-list list) (map cdr (sort-alist (map (cut cons (random-integer ##max-fixnum) <>) list))))
(def (make-alist n (f number->string)) (map (lambda (i) (cons i (f i))) (iota n 1)))
(def alist-equal? (comparing-key test: equal? key: sort-alist))

(def al-10-latin (make-alist 10 roman-numeral<-integer))
(def al-100-decimal (make-alist 100))
(def al-100-latin (make-alist 100 roman-numeral<-integer))
(def al-1 (shuffle-list al-100-decimal))
(def al-2 (filter (compose even? car) al-100-decimal))
(def al-3 (filter (lambda (x) (> (string-length (cdr x)) 5)) al-100-latin))
(def al-4 '((42 . "42") (1729 . "1729") (666 . "666")))
(def al-5 (sort-alist (delete-duplicates (append al-3 al-4) (comparing-key test: = key: car))))

(def current-verbosity (make-parameter #t))
(defrule (X tag rest ...) (DBG (and (current-verbosity) tag) rest ...))

(def (read-only-linear-table-test T)
  (table-test-case T "read-only linear table test"
    (def m-10-latin (<-alist al-10-latin))
    (def m-100-decimal (<-alist al-100-decimal))
    (def m-100-latin (<-alist al-100-latin))
    (def m-1 (<-alist al-1))
    (def m-2 (<-alist al-2))
    (def m-3 (<-alist al-3))
    (def m-4 (<-alist al-4))
    (def m-5 (<-alist al-5))
    (X 'empty)
    (check-equal? (F .list<- (E .empty)) '())
    (check-equal? (F .empty? (E .empty)) #t)
    (X 'ref)
    (check-equal? (F .ref (<-alist '((57 . "57") (10 . "10") (12 . "12"))) 12) "12")
    (for-each! al-1 (match <> ([k . v] (assert-equal! (F .ref m-1 k) v))))
    (check-exception (F .ref m-1 101) true)
    (check-exception (F .ref m-1 "57") true)
    (X '<-alist<-)
    (check-equal? (alist<- (<-alist '((1 . 1)))) '((1 . 1)))
    (check-equal? (alist<- (<-alist '((1 . 1) (3 . 3)))) '((1 . 1) (3 . 3)))
    (check-equal? (alist<- (<-alist al-10-latin)) al-10-latin)
    (check-equal? (alist<- (<-alist al-100-decimal)) al-100-decimal)
    (check-equal? (alist<- (<-alist al-100-latin)) al-100-latin)
    (X 'min-binding)
    (check-equal? (F .min-binding/opt m-4) (some (cons 42 "42")))
    (check-equal? (F .min-binding m-4) (cons 42 "42"))
    (check-equal? (F .min-binding/opt (E .empty)) #f)
    (check-exception (F .min-binding (E .empty)) true)
    (X 'max-binding)
    (check-equal? (F .max-binding/opt m-4) (some (cons 1729 "1729")))
    (check-equal? (F .max-binding m-4) (cons 1729 "1729"))
    (check-equal? (F .max-binding/opt (E .empty)) #f)
    (check-exception (F .max-binding (E .empty)) true)
    (X 'foldl)
    (check-equal? (F .foldl (constantly #t) #f (E .empty)) #f)
    (check-equal? (F .foldl (lambda (k _ a) (+ k a)) 0 m-100-latin) (* 1/2 100 101))
    (X 'foldr)
    (check-equal? (F .foldr (constantly #t) #f (E .empty)) #f)
    (check-equal? (F .foldr (lambda (k _ a) (+ k a)) 0 m-100-latin) (* 1/2 100 101))
    (X 'count)
    (check-equal? (F .count (E .empty)) 0)
    (check-equal? (F .count m-100-latin) 100)
    (X 'for-each)
    (check-equal? (with-list-builder (c) (F .for-each (lambda (_ v) (c v)) m-10-latin))
                  '("I" "II" "III" "IV" "V" "VI" "VII" "VIII" "IX" "X"))
    ))

(def (simple-linear-table-test T)
  (table-test-case T "simple linear table test"
    ;;; TODO: test each and every function in the API
    (X 'acons)
    (check-equal? (alist<- (F .acons 0 "0" (E .empty))) '((0 . "0")))
    (check-equal? (alist<- (F .acons 2 "2" (<-alist '((1 . "1") (3 . "3")))))
                  '((1 . "1") (2 . "2") (3 . "3")))

    (X 'acons-and-join)
    (check-equal? (alist<- (F .acons 0 "0" (F .join (F .singleton 1 "1") (F .singleton 2 "2"))))
                  '((0 . "0") (1 . "1") (2 . "2")))

    (X 'acons-and-count)
    (check-equal? (F .count (F .acons 101 "101" (<-alist al-1))) 101)

    (X 'remove)
    (check-equal? (alist<- (F .remove (F .singleton 42 "42") 42)) '())
    (check-equal? (alist<- (F .remove (F .singleton 42 "42") 43)) '((42 . "42")))
    (check-equal? (alist<- (F .remove (<-alist '((13 . "13") (27 . "27"))) 13)) '((27 . "27")))
    (check-equal? (alist<- (F .remove (<-alist '((13 . "13") (27 . "27"))) 27)) '((13 . "13")))
    (check-equal? (F .count (F .remove (<-alist al-1) 42)) 99)
    (check-equal? (F .ref/opt (F .remove (<-alist al-1) 42) 42) #f)
    (check-equal? (F .ref/opt (F .remove (<-alist al-1) 42) 41) (some "41"))

    (X 'foldl)
    (check-equal? (alist<- (F .foldl (E .acons) (<-alist '((20 . "20") (30 . "30"))) (<-alist (make-alist 2)))) '((1 . "1") (2 . "2") (20 . "20") (30 . "30")))
    (check-equal? (F .count (F .foldl (E .acons) (<-alist al-100-decimal) (<-alist al-100-latin))) 100)

    (X 'foldr)
    (check-equal? (alist<- (F .foldr (E .acons) (<-alist '((20 . "20") (30 . "30"))) (<-alist (make-alist 2)))) '((1 . "1") (2 . "2") (20 . "20") (30 . "30")))
    (check-equal? (F .count (F .foldr (E .acons) (<-alist al-100-decimal) (<-alist al-100-latin))) 100)

    (X 'join)
    (check-equal? (alist<- (F .join (<-alist al-3) (<-alist al-4))) al-5)
    (check-equal? (F .empty? (F .join (E .empty) (E .empty))) #t)
    (check-equal? (alist<- (F .join (<-alist '((1 . "1") (2 . "2"))) (<-alist '((5 . "5") (6 . "6")))))
                  '((1 . "1") (2 . "2") (5 . "5") (6 . "6")))
    (check-equal? (F .count (F .join (<-alist al-10-latin) (<-alist al-100-latin))) 100)

    (X 'divide)
    (check-equal? (values->list (F .divide (E .empty))) [#f #f])
    (let-values (((x1 x2) (F .divide (F .singleton 23 "23"))))
      (check-equal? (alist<- x1) '((23 . "23")))
      (check-equal? x2 #f))
    (let-values (((x1 x2) (F .divide (<-alist '((23 . "23") (69 . "69"))))))
      (check-equal? (alist<- x1) '((23 . "23")))
      (check-equal? (alist<- x2) '((69 . "69"))))
    (let-values (((x1 x2) (F .divide (<-alist '((41 . "41") (42 . "42"))))))
      (check-equal? (alist<- x1) '((41 . "41")))
      (check-equal? (alist<- x2) '((42 . "42"))))
    (let ()
      (defvalues (d1 d2) (F .divide (<-alist al-10-latin)))
      (check-equal? (+ (F .count d1) (F .count d2)) 10)
      (check-equal? (alist<- (F .join d1 d2)) al-10-latin))
    (let ()
      (defvalues (d1 d2) (F .divide (<-alist al-100-latin)))
      (check-equal? (+ (F .count d1) (F .count d2)) 100)
      (check-equal? (alist<- (F .join d1 d2)) al-100-latin))

    ;; Repeatedly divide a map into pairs of smaller sub-maps.
    (let (q (make-queue))
      (enqueue! q (<-alist al-100-decimal))
      (until (queue-empty? q)
        (let* ((m (dequeue! q))
               (s (F .count m)))
          (defvalues (x y) (F .divide m))
          (def cx (if x (F .count x) 0))
          (def cy (if y (F .count y) 0))
          (assert-equal! (+ cx cy) (F .count m))
          (assert-equal! (or (and (plus? cx) (plus? cy))
                            (and (= cx 1) (not y))
                            (and (not x) (not y)))
                        #t)
          (when (and x y)
            (assert-equal! (alist<- (F .join x y)) (alist<- m))
            (enqueue! q x) (enqueue! q y)))))

    (X 'update)
    (check-equal? (alist<- (foldl (lambda (k m) (F .update k (lambda (v) (number->string k)) m))
                                  (<-alist al-100-latin)
                                  (iota 100 1)))
                  al-100-decimal)

    (X 'iter<-)
    (check-equal? (for/collect (kv (F .iter<- (<-alist al-10-latin))) kv)
                  '((1 . "I") (2 . "II") (3 . "III") (4 . "IV") (5 . "V")
                    (6 . "VI") (7 . "VII") (8 . "VIII") (9 . "IX") (10 . "X")))))

 (def (harder-linear-table-test T)
   (table-test-case T "harder linear table test"
     ;; (X 'join/list)
     ;; TODO: add tests

     (X 'divide/list)
     (check-equal? (F .divide/list (E .empty)) '())

     ;; Repeatedly divide/list a map into pairs of smaller sub-maps.
     (def l (with-list-builder (c)
              (let (q (make-queue))
                (enqueue! q (<-alist al-100-decimal))
                (until (queue-empty? q)
                  (let* ((m (dequeue! q))
                         (s (F .count m))
                         (l (F .divide/list m))
                         (sl (map (.@ T .count) l)))
                    (assert-equal! (every plus? sl) #t)
                    (assert-equal! (foldl + 0 sl) s)
                    (cond
                     ((< 1 s) (for-each (cut enqueue! q <>) l))
                     (else (assert-equal! (length l) 1) (c (car l)))))))))
     (check-equal? (alist<- (F .join/list l)) al-100-decimal)))

(def (multilinear-table-test T)
  (table-test-case T "multilinear table test"
    (let (m (<-alist al-10-latin))
      (alist-equal? (alist<- m) (alist<- (F .join m m))))))

(def (regression-tests T)
  (table-test-case T "regression tests on read-only linear tables"
    (X 'divide) ;; from a bug in LIL's avl-based number-map
    (defvalues (x y) (F .divide (<-alist '((557088 . 7) (229378 . 79)))))
    (check-equal? (length (alist<- x)) 1)
    (check-equal? (length (alist<- y)) 1)
    (check-equal? (sort-alist (append (alist<- x) (alist<- y))) '((229378 . 79) (557088 . 7)))))

(def (update-tests T)
  (table-test-case T "update tests" ;; initially ported from legilogic_lib
    (test-case "update exclaim"
      (def t (F .<-list '((13 . "a") (21 . "bee") (34 . "c"))))
      (def (exclaim s) (string-append s "!"))
      (check-equal? (alist<- (F .validate (F .update 21 (traced-function 'exclaim exclaim) t)))
                    '((13 . "a") (21 . "bee!") (34 . "c"))))
    (test-case "update/opt toggle"
      (def t1 (F .<-list '((13 . "a") (21 . "bee") (34 . "c"))))
      (def t2 (F .<-list '((13 . "a") (34 . "c"))))
      (def toggle (match <> ((some _) #f) (#f (some "I'm back"))))
      (check-equal? (alist<- (F .update/opt 21 toggle t1)) (alist<- t2))
      (check-equal? (alist<- (F .update/opt 21 toggle t2))
                    '((13 . "a") (21 . "I'm back") (34 . "c"))))
    (test-case "update/opt 1597 toggle"
      (def t1 (F .<-list '((34 . "34") (13 . "13"))))
      (def t2 (F .<-list '((13 . "13") (34 . "34") (1597 . "veni, vidi"))))
      (def toggle (match <> ((some _) #f) (#f (some "veni, vidi"))))
      (check-equal? (alist<- (F .update/opt 1597 toggle t1)) (alist<- t2))
      (check-equal? (alist<- (F .update/opt 1597 toggle t2)) (alist<- t1))
      (def t3 (F .singleton 1597 "veni, vidi"))
      (check-equal? (alist<- (F .update/opt 1597 toggle (E .empty))) (alist<- t3))
      (check-equal? (alist<- (F .update/opt 1597 toggle t3)) '()))))

(def (table-tests T)
  ;;  (read-only-linear-table-test T)
  (simple-linear-table-test T)
  (harder-linear-table-test T)
  ;;  (multilinear-table-test T)
  (read-only-linear-table-test T)
  (regression-tests T)
  (update-tests T))
