(defun sym-is (sym name) (and (symbolp sym) (equal (symbol-name sym) name)))
(defmacro token! (tok &optional (want (symbol-name tok)))
   `(let ((actual (symbol-name ,tok)))
      (unless (equal ,want actual) (error "Expected token ~F but instead found ~F" ,want actual))))

(defun psh (lst e) (append lst (list e)))
(defmacro psh! (sym e) `(setf ,sym (psh ,sym ,e)))
(defmacro car! (sym) `(let ((fst (car ,sym))) (setf ,sym (cdr ,sym)) fst))

(defun clike-while-tag-top (sym-or-nil)
   (intern
      (concatenate
         'string
         "clike-while-top"
         (if sym-or-nil
            (concatenate 'string "-" (symbol-name sym-or-nil))
            "")
      )
   )
)

(defun clike-while-tag-end (sym-or-nil)
   (intern
      (concatenate
         'string
         "clike-while-end"
         (if sym-or-nil
            (concatenate 'string "-" (symbol-name sym-or-nil))
            "")
      )
   )
)

(declaim (ftype function clike-scope))
(defun clike-expr (ts)
   (let (curr out)
      (setf curr (car! ts))

      (if (symbolp curr)
         (cond
            ((sym-is curr "BREAK") (progn
               (let ((next (car! ts)))
                  (unless (listp next)
                     (error "`break' must be invoked, it cannot be a bareword!"))
                  (if (> (length next) 1)
                     (error "too many arguments to `break' (provide at most 1)"))
                  (setf out `(go ,(clike-while-tag-end (car next))))
               )
            ))
            ((sym-is curr "CONTINUE") (progn
               (let ((next (car! ts)))
                  (unless (listp next)
                     (error "`continue' must be invoked, it cannot be a bareword!"))
                  (if (> (length next) 1)
                     (error "too many arguments to `continue` (provide at most 1)"))
                  (setf out `(go ,(clike-while-tag-top (car next))))
               )
            ))
            ((and ts (car ts) (listp (car ts))) (progn
               ; curr(variable) and curr(variable nil) because we don't want
               ; to expand variable into a function call
               ; function call
               ; +(2 *(4 10))
               ; wanted to pass a list as an argument?
               ; fn(list(1 2 3))
               ; or
               ; fn([ 1 2 3 ])

               (psh! out curr) ; function name

               (let ((args (car! ts)) res-arg)
                  (loop
                     (if (null args)
                        (return))
                     (setf res-arg (clike-expr args))
                     (psh! out (car res-arg))
                     (setf args (cdr res-arg))
                  )
               )
            ))
            ((sym-is (car ts) "<-") (progn
               ; function call with spread arguments
               ; + <- '(1 2)
               ; terpri <- nil
               (car! ts)
               (setf out `(apply ',curr ,(car! ts)))
            ))
            ((sym-is curr "[") (progn
               ; list literal
               ; [ 1 2 3 ]
               (psh! out 'list)

               (loop
                  (if (null ts)
                     (error "Expecting closing bracket list literal!~%"))

                  (if (sym-is (car ts) "]")
                     (return))

                  (let ((res-element (clike-expr ts)))
                     (psh! out (car res-element))
                     (setf ts (cdr res-element))
                  )
               )
               (car! ts) ; remove ]
            ))

            ; variable stuff
            ((sym-is (car ts) "=") (progn
               ; assignment
               (car! ts)
               (let ((res-val (clike-expr ts)))
                  (progn
                     (setf out `(setf ,curr ,(car res-val)))
                     (setf ts (cdr res-val))
                  )
               )
            ))
            (t (progn
               ; variable access
               (setf out curr)
            ))
         )

         ; else
         (setf out curr)
      )

      (cons out ts) ; expr in car, excess tokens in cdr
   )
)

(defun clike-let (ts)
   (let (key res-val res-scope)
      (setf key (car! ts))
      (token! (car! ts) "=")

      (setf res-val (clike-expr ts))
      (setf ts (cdr res-val))

      (setf res-scope (clike-scope ts))
      (setf ts (cdr res-scope))

      (cons `(let ((,key ,(car res-val))) ,(car res-scope)) ts)
   )
)

(defun clike-while (ts)
   (let (res-cond res-body tag-top tag-end)
      (if (listp (car ts))
         (let ((next (car! ts)))
            (if (> (length next) 1)
               (error "while(<at most 1 symbol here>)"))
            (setf tag-top (clike-while-tag-top (car next)))
            (setf tag-end (clike-while-tag-end (car next)))
         )
         (progn
            (setf tag-top (clike-while-tag-top nil))
            (setf tag-end (clike-while-tag-end nil))
         )
      )

      (setf res-cond (clike-expr ts))
      (setf ts (cdr res-cond))
      (token! (car! ts) "{")

      (setf res-body (clike-scope ts))
      (setf ts (cdr res-body))
      (token! (car! ts) "}")

      (cons
         `(tagbody
            ,tag-top
            (unless ,(car res-cond) (go ,tag-end))
            ,(car res-body)
            (go ,tag-top)
            ,tag-end
         )
         ts
      )
   )
)

(defun clike-if (ts)
   (let (res-cond res-body res-else)
      (setf res-cond (clike-expr ts))
      (setf ts (cdr res-cond))
      (token! (car! ts) "{")

      (setf res-body (clike-scope ts))
      (setf ts (cdr res-body))
      (token! (car! ts) "}")

      (if (sym-is (car ts) "ELSE")
         (let (next)
            (car! ts) ; remove else token
            (setf next (car! ts))
            (if (sym-is next "IF")
               (progn
                  (setf res-else (clike-if ts))
                  (setf ts (cdr res-else)))
               (progn
                  (setf res-else (clike-scope ts))
                  (setf ts (cdr res-else))
                  (token! (car! ts) "}"))
            )
         )
      )
      (cons `(if ,(car res-cond) ,(car res-body) ,(car res-else)) ts)
   )
)

(defun clike-scope (ts)
   (let ((out `(progn)) res)
      (loop
         (cond
            ((null ts) (progn
               (return)
            ))
            ((sym-is (car ts) "}") (progn
               (return)
            ))
            ((sym-is (car ts) "LET") (progn
               (setf res (clike-let (cdr ts)))
               (psh! out (car res))
               (setf ts (cdr res))
            ))
            ((sym-is (car ts) "WHILE") (progn
               (setf res (clike-while (cdr ts)))
               (psh! out (car res))
               (setf ts (cdr res))
            ))
            ((sym-is (car ts) "IF") (progn
               (setf res (clike-if (cdr ts)))
               (psh! out (car res))
               (setf ts (cdr res))
            ))
            (t (progn
               (setf res (clike-expr ts))
               (psh! out (car res))
               (setf ts (cdr res))
            ))
         )
      )
      (cons out ts)
   )
)

(defmacro clike (&rest ts)
   (let ((res-scope (clike-scope ts)))
      (if (cdr res-scope)
         (error "clike-toplevel: unexpected token `~F'~%" (caadr res-scope))
         (car res-scope)
      )
   )
)

(clike
   let i = 0
   while <(i 10) {
      if =(0 mod(i 2)) {
         princ("nope")
         i = +(i 1)
         continue()
      }

      print(i)
      terpri <- nil
      i = +(i 1)
   }
   exit <- nil;
)
