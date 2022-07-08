(macro process [body]

    (local ops {})
    (each [i v (ipairs ["=" "or=" "and=" "..=" "+="
                        "-=""*=" "/=" "%=" "^=" "or"
                        "and" ".." "<" ">" "<=" ">="
                        "!=" "==" "+" "-" "*" "/" "%"
                        "^" "."])]
        (tset ops v true))

    (fn error [msg tab]
        (assert false msg tab))

    (fn to-table [a]
        (local new [])
        (each [i v (ipairs a)]
            (tset new i v))
        new)

    (fn copy [a]
        (if (and (= (type a) :table) (not (sym? a)))
            (do
                (local result
                    (if (list? a)
                        (list)
                        []))
                (each [i v (ipairs a)]
                    (tset result i v))
                result)
            a))

    (fn wrap [a s end]
        (local e (or end (length a)))
        ; if more than one item here
        (when (< s e)
            ; copy everything into an inner table
            (local tab (list))
            (for [i s e]
                (table.insert tab (table.remove a s)))
            (table.insert a s tab)))

    (fn seq-wrap [a s end]
        (local e (or end (length a)))
        (assert (>= (- e s) -1) "compiler bug: bad seq wrap " a)
        (local tab [])
        (for [i s e]
            (table.insert tab (table.remove a s)))
        (table.insert a s tab))

    (fn in? [container sym]
        (for [i 1 (length container)]
            (when (= sym (. container i))
                (lua "return i"))))

    (fn inline-ops! [a ops]
        (for [i 1 (length ops)]
            (tset ops i (sym (. ops i))))
        (for [i (- (length a) 1) 2 -1]
            ;; TODO keep going back until a different op is encountered
            (when (in? ops (. a i))
                (wrap a (+ i 1))
                (wrap a 1 (- i 1))
                (table.insert a 1 (table.remove a 2))
                (lua "return true"))))

    (fn inline-op! [a op-str]
        (var op (sym op-str))
        (local len (length a))
        (var j len)
        (for [i (- len 1) 2 -1]
            (when (= op (. a i))
                (table.remove a i)
                (wrap a i (- j 1))
                (set j (- i 1))))
        (when (not= j len)
            (wrap a 1 j)
            (table.insert a 1 op)
            true))

    (fn check-ops [a]
        (assert (= (% (length a) 2) 1) "badly formed operators" a)
        (for [i 1 (length a)]
            (if (= (% i 2) 1)
                (assert (not (. ops (. a i))) "unexpected operator" (. a i))
                (assert (. ops (. a i)) "expected an operator" (. a i)))))
        

    (fn inline-op-strict! [a op]
        (check-ops a)
        (inline-op! a op))

    (fn inline-ops-strict! [a ops]
        (check-ops a)
        (inline-ops! a ops))

    (fn delistify [a]
        (var a a)
        (var RECURSE true)
        (when (list? a)

            ; fixes square brackets []
            (when (= (. a 1) (sym :fsc-reserved-square-bracket))
                (let [b (sequence)]
                    (each [i v (ipairs a)]
                        (if (not= i 1)
                            (tset b (- i 1) (delistify v))))
                    (set a b)))

            ; fixes curly brackets {}
            (when (= (. a 1) (sym :fsc-reserved-curly-bracket))
                (let [b {}]
                    (var i 2)
                    (while (. a i)
                        (match [(. a i) (= (sym "=" ) (. a (+ 1 i))) (. a (+ 2 i))]
                            ; ident_on_its_own
                            (where [key false] (sym? key))
                            (do
                                (tset b (tostring key) key)
                                (set i (+ 1 i)))
                            ; a = b
                            (where [key true ?val] (sym? key))
                            (do
                                (tset b (tostring key) (delistify ?val))
                                (set i (+ 3 i)))
                            ; "a" = b
                            (where [key true ?val] (= (type key) :string))
                            (do
                                (tset b (tostring key) (delistify ?val))
                                (set i (+ 3 i)))
                            ; [a] = b
                            (where [key true ?val]
                                (and (list? key)
                                     (= (. key 1) (sym :fsc-reserved-square-bracket))))
                            (do
                                (wrap key 2)
                                (tset b
                                      (delistify (. key 2))
                                      (delistify ?val))
                                (set i (+ 3 i)))

                            _   (error "bad table literal" a)))
                    (set a b)))


            (when (list? a)


                ; merge if statements
                (var i 1)
                (while (<= i (length a))
                    (when (and
                            (= (type (. a i)) :table)
                            (= (. a i 1) (sym :if)))
                        (tset (. a i) 1 (sym :do))
                        (tset a i (list (sym :if) (table.remove (. a i) 2) (. a i)))
                        (while (and
                                (<= (+ i 1) (length a))
                                (= (type (. a (+ i 1))) :table)
                                (= (. a (+ i 1) 1) (sym :elseif)))
                            (tset (. a (+ i 1)) 1 (sym :do))
                            (table.insert (. a i)
                                (table.remove (. a (+ i 1)) 2))
                            (table.insert (. a i)
                                (table.remove a (+ i 1))))
                        (when (and
                                (<= (+ i 1) (length a))
                                (= (type (. a (+ i 1))) :table)
                                (= (. a (+ i 1) 1) (sym :else)))
                            (tset (. a (+ i 1)) 1 (sym :do))
                            (table.insert (. a i)
                                (table.remove a (+ i 1)))))
                    (set i (+ i 1)))

                ; merge empty let statements
                (var i 1)

                ; go through all but last statement
                (while (< i (length a))
                    (local j (+ 1 i))
                    (when (and
                            (= (type (. a i)) :table)
                            (= (. a i 1) (sym :let))
                            (= (length (. a i)) 2)
                            (= (type (. a j)) :table)
                            (= (. a j 1) (sym "=")))
                        (table.insert (. a j) 1 (sym "fn"))
                        (table.insert (. a j) 2 (. a i 2))
                        (tset (. a j) 3 [])
                        (table.remove a i))
                    (set i (+ i 1)))
                (when (sym? (. a 1))
                    ; special forms
                    (match (tostring (. a 1))
                        :spice-quote (tset a 1 (sym "quote"))
                        :local
                        (do
                            (local pos (in? a (sym "=")))
                            (assert pos (.. "expected \"=\" sign in local" (tostring a)) a)
                            (tset a 1 (sym "var"))
                            (wrap a 3 (- pos 1))
                            (table.remove a pos)
                            (wrap a pos))
                        ; let x y z = a b c -> fn x [y z] (a b c)
                        :let
                        (do
                            (local pos (in? a (sym "=")))
                            (assert pos "expected \"=\" sign in let" a)
                            (if
                                ; case with no args
                                (= pos 3)
                                (do
                                    (tset a 1 (sym "local"))
                                    (wrap a 3 (- pos 1))
                                    (table.remove a pos)
                                    (wrap a pos))
                                ; case with args
                                (> pos 3)
                                (do
                                    (tset a 1 (sym "fn"))
                                    (seq-wrap a 3 (- pos 1))
                                    (table.remove a 4))))
                        :macro
                        (do
                            (local pos (in? a (sym "=")))
                            (assert pos "expected \"=\" sign in macro" a)
                            (assert (> pos 2) "expected name in macro" a)
                            (seq-wrap a 3 (- pos 1))
                            (table.remove a 4)
                            (tset a 1 (sym "macro")))
                        ; match (expr expr)
                        ;    (match clause)
                        ;        match body
                        :match
                        (do
                            (local out (list))
                            (table.insert out (. a 1))
                            (table.insert out (. a 2))
                            (for [i 3 (length a)]
                                (when (and (list? (. a i 1))
                                           (= (. a i 1 2) (sym :where)))
                                      (table.remove (. a i 1) 2)
                                      (table.insert (. a i 1) 1 (sym :where)))
                                (table.insert out (. a i 1))
                                (tset (. a i) 1 (sym :do))
                                (table.insert out (. a i)))
                            (set a out))
                        (where name (in? [:for :collect :icollect] name))
                        (do
                            (set RECURSE false)
                            (local args [])
                            ; if you see an =, go until there's no more numbers
                            ; if you see a 'in'. go one more and then you're done
                            (var state :init)
                            (var kind nil)
                            (while
                                (do
                                    (var val (table.remove a 2))
                                    (if (not val)
                                        (error "bad for loop" a))
                                    (if
                                        (and (= state :init) (= val (sym :in)))
                                        (do
                                            (set kind :in)
                                            (set state :in))
                                        (and (= state :init) (= val (sym "=")))
                                        (do
                                            (set kind :eq)
                                            (set state :eq))
                                        (= state :eq)
                                        (do
                                            (each [_ v (ipairs val)]
                                                (table.insert args (delistify v)))
                                            (set val nil)
                                            (set state :exit))
                                        (= state :in)
                                        (set state :exit))
                                    (when (not (or (= val (sym :nil))
                                                   (= val (sym :in))
                                                   (= val (sym "="))))
                                        (table.insert args (delistify val)))
                                    (not= state :exit)))
                            (when (and (list? (. a 2)) (= (. a 2 1) (sym :until)))
                                (table.insert args :until)
                                (local untilblock (table.remove a 2))
                                (tset untilblock 1 (sym :do))
                                (table.insert args (delistify untilblock)))
                            (table.insert a 2 args)
                            (for [i 3 (length a)]
                                (tset a i (delistify (. a i))))
                            (match (values (tostring name) kind)
                                (:for :in) (tset a 1 (sym :each))
                                (where (collect-name :eq) (in? [:collect :icollect] collect-name))
                                (do
                                    (tset a 1 (sym :for))
                                    (local collection (gensym))
                                    (local body (list (sym :do)))
                                    (while (. a 3)
                                        (table.insert body (table.remove a 3)))
                                    (tset a 3
                                        (if
                                            (= collect-name :collect)
                                            (do
                                                (local key (gensym))
                                                (local value (gensym))
                                                (list (sym :match) body
                                                    (list key value)
                                                    (list (sym :tset) collection key value)))
                                            (= collect-name :icollect)
                                            (do
                                                (list (sym :tset) collection
                                                    (list (sym :+) (list (sym :length) collection) 1)
                                                    body))))
                                    (set a
                                        (list (sym :let) [collection {}] a collection)))))))
                             
                (if
                    (inline-ops! a ["=" "or=" "and=" "..=" "+=" "-=""*=" "/=" "%=" "^="])
                    (do
                        ; transform += into =
                        (when (not= (. a 1) (sym "="))
                            (local inner-op (sym (: (tostring (. a 1)) :sub 1 -2)))
                            (tset a 1 (sym "="))
                            (tset a 3 (list inner-op (copy (. a 2)) (. a 3)))
                            (tset a 2 (copy (. a 2))))
                        ; foo = 10 ==> set foo 10
                        ; (foo @ 2) = 10 ==> tset foo 2 10
                        ; (foo @ 2 @ 3) = 10 ==> tset (foo @ 2) 3 10
                        ; (@ foo 2 3) = 10 ==> tset (@ foo 2) 3 10
                        (if (and (list? (. a 2))
                                 (not (= (. a 2 1) (sym :fsc-reserved-curly-bracket)))
                                 (not (= (. a 2 1) (sym :fsc-reserved-square-bracket))))
                            ; tset variation
                            (do (var expr (. a 2))
                                (local x (table.remove expr))
                                (if
                                    ; infix
                                    (= (. expr 2) (sym "."))
                                    (do (table.remove expr)
                                        (when (= (length expr) 1)
                                            (set expr (. expr 1))))
                                    ; not infix
                                    (= (. expr 1) (sym "."))
                                    (do (when (= (length expr) 2)
                                            (set expr (. expr 2))))
                                    (error "invalid assignment lvalue" expr))
                                (tset a 1 (sym :tset))
                                (table.insert a 2 expr)
                                (tset a 3 x))
                            ; normal set variation
                            (tset a 1 (sym :set))))
                    (inline-op! a "or") nil
                    (inline-op! a "and") nil
                    (inline-ops! a ["<" ">" "<=" ">=" "!=" "=="])
                    (do
                        (when (= (. a 1) (sym "!="))
                            (tset a 1 (sym "not=")))
                        (when (= (. a 1) (sym "=="))
                            (tset a 1 (sym "="))))
                    (inline-op! a "..") nil
                    (inline-ops! a ["+" "-"]) nil
                    (inline-ops! a ["*" "/" "%"]) nil
                    ; would go here in precedence but it's not a binop
                    ; (inline-op! a "not") nil
                    (inline-op! a "^") nil
                    (inline-op! a ".") nil
                    ; 'foo bar a b c -> : bar :foo a b c
                    (and (list? (. a 1)) (= (. a 1 1) (sym :fsc-reserved-single-quote)))
                    (do
                        (local method (tostring (table.remove (. a 1))))
                        (tset a 1 (sym ":"))
                        (table.insert a 3 method))))
            (when RECURSE
                (each [k v (ipairs a)]
                    (tset a k (delistify v)))))
        a)
    (delistify body))
