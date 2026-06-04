;;; Aa-VM --- Aa-machine implementation in Scheme
;;; Copyright © 2025 Adam Faiz <adam.faiz@disroot.org>
;;;
;;; This file is part of Aa-VM.
;;;
;;; Aa-VM is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; Aa-VM is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with Aa-VM.  If not, see <http://www.gnu.org/licenses/>.

(let* ((arg1 '(reg 0))
       (arg2 '(reg 1))
       (arg1-unify '(reg-unify 0))
       (arg2-unify '(reg-unify 1))
       (undo? '(env 0))
       (save? '(env 1))
       (link? '(env 2))
       (quittable? '(env 3))
       (styling? '(env 4))
       (colour? '(env 5))
       (alignment? '(env 6))
       (top-status? '(env 7))
       (inline-status? '(env 8))
       (dialog-empty-lst '(reg #x3e))
       (dialog-empty-lst-unify '(reg-unify #x3e))
       (pass '(jmp (jump passed)))
       (call (lambda (proc) `(jmpl-simple (jump ,proc))))
       (run-tests
	(lambda (tests)
	  (append '(run-tests
		    (choice-push (byte 0) (jump crash))
		    (env-push (byte 6))
		    (print-a-str-a "Running tests:")(line))
		  (map call tests)
		  '((env-pop)(jmp (jump end))))))
       (info
	(lambda (label flag text next)
	  `(,label
	    (raw-eq? 0 ,flag (jump ,next))
	    (print-a-str-a ,text)(line))))
       (test
	(lambda (label msg body)
	  (append `(,label (print-a-str-a ,msg)) body '((backtrack)))))
       (check (lambda (l m b) (test l m (append b (list pass)))))
       (skip (lambda (l m) (check l m '()))))
  `((start
     (eq? (num 1) ,arg1 (jump tco-no)) ; Heap overflow
     (print-a-str-a "Welcome to the Å-machine!")
     (par)
     (print-a-str-a "This is a test suite designed to stress test the opcodes,")
     (print-a-str-a "and hopefully point out any bugs in a terp.")
     (par)
     (jmpl-simple (jump terp-info))
     (jmp (jump run-tests)))
    (crash
     (print-a-str-a "One of the tests failed when it's not supposed to.")(line)
     (print-a-str-a "The output history should show what the issue is.")(line)
     (jmp (jump end)))
    (terp-info
     (env-push (byte 9))
     (vm-info can-undo? ,undo?)
     (vm-info can-save? ,save?)
     (vm-info can-hyperlink? ,link?)
     (vm-info can-quit? ,quittable?)
     (vm-info can-style? ,styling?)
     (vm-info can-colour? ,colour?)
     (vm-info can-align? ,alignment?)
     (vm-info has-top-status? ,top-status?)
     (vm-info has-inline-status? ,inline-status?)
     (print-a-str-a "This interpreter supports the following features:")(line))
    ,(info 'check-undo undo? "UNDO" 'check-save)
    ,(info 'check-save save? "SAVEFILE" 'check-link)
    ,(info 'check-link link? "LINK" 'check-quit)
    ,(info 'check-quit quittable? "QUIT" 'check-style)
    ,(info 'check-style styling? "STYLING" 'check-colour)
    ,(info 'check-colour colour? "COLOUR" 'check-align)
    ,(info 'check-align alignment? "TEXT ALIGNMENT" 'check-top-status)
    ,(info 'check-top-status top-status? "TOP STATUS" 'check-inline-status)
    ,(info 'check-inline-status inline-status? "INLINE STATUS" 'next)
    (next (par)(proceed))
    ,(run-tests '(test-backtrack
		  test-nop
		  test-cont-set
		  test-proceed
		  test-jmp
		  test-jmp-multi
		  test-jmpl-multi
		  test-jmp-simple
		  test-jmpl-simple
		  test-jmp-tail
		  test-tail
		  test-env-push
		  test-env-pop
		  test-env-pop-proceed
		  test-choice-push
		  test-choice-pop
		  test-choice-pop-push
		  test-choice-cut
		  test-choice-get-set
		  test-assign
		  test-make-var
		  test-make-pair
		  test-aux-raw-push
		  test-aux-val-push
		  test-aux-list-chk-pop
		  test-aux-list-match-pop
		  test-list-split
		  test-stop
		  test-store-word
		  test-store-byte
		  test-store-val
		  test-flag-set
		  test-unlink
		  test-parent-set
		  test-raw-eq?
		  test-bound?
		  test-empty?
		  test-num?
		  test-pair?
		  test-obj?
		  test-word?
		  test-uword?
		  test-unify?
		  test-gt?
		  test-eq?
		  test-mem-eq?
		  test-flag?
		  test-cwl?
		  test-num-add
		  test-num-sub
		  test-num-mul
		  test-num-div
		  test-num-mod
		  test-num-rand
		  test-num-inc
		  test-num-dec
		  test-raw-inc
		  test-raw-dec
		  test-print
		  test-choice-env
		  test-aux-car-cdr
		  test-word-compare
		  test-tco))
    (passed
     (print-a-str-a "yes")(line)
     (proceed))
    (tco-no
     (print-a-str-a "no (unsupported)")(line)
     (jmpl-simple (jump terp-info))
     (jmp (jump end)))
    (tco-yes (print-n-str-a "yes")(env-pop-proceed))
    ,(test 'test-backtrack "Choice backtrack:"
	   '((choice-push (byte 10) (jump passed))
	     (backtrack)))
    ,(check 'test-nop "NOP:" '((nop)))
    (restore-cont (env-pop-proceed))
    ,(check 'test-cont-set "CONT SET:"
	   '((env-push (byte 0))
	     (cont-set (jump restore-cont))))
    ,(skip 'test-proceed "PROCEED:")
    ,(skip 'test-jmp "JMP:")
    (restore-sim (choice-pop (byte 0)) ,pass)
    ,(test 'test-jmp-multi "Multi-jump:" '((jmp-multi (jump passed))))
    ,(test 'test-jmpl-multi "Multi-query:"
	   '((choice-push (byte 0) (jump crash))
	     (jmpl-multi (jump restore-sim))))
    ,(test 'test-jmp-simple "Simple jump:" '((jmp-simple (jump passed))))
    ,(skip 'test-jmpl-simple "Query:")
    ,(test 'test-jmp-tail "Tail call:" '((jmp-tail (jump passed))))
    (reset-handler
     (choice-pop (byte 0)) ,pass)
    (simple-cut
     (choice-push (byte 0) (jump reset-handler))
     (tail)(backtrack))
    ,(test 'test-tail "Tail:" '((jmp-multi (jump simple-cut))))
    ,(skip 'test-env-push "Push ENV frame:")
    ,(check 'test-env-pop "Pop ENV frame:" '((env-push (byte 0))(env-pop)))
    ,(skip 'test-env-pop-proceed "ENV pop proceed:")
    ,(skip 'test-choice-push "Push CHO frame:")
    ,(skip 'test-choice-pop "Pop CHO frame:")
    ,(test 'test-choice-pop-push "CHO pop push:"
	   '((choice-push (byte 0) (jump crash))
	     (choice-pop-push (byte 0) (jump passed))
	     (backtrack)))
    ,(test 'test-choice-cut "Cut CHO frame:"
	   '((choice-push (byte 0) (jump passed))
	     (choice-push (byte 0) (jump crash))
	     (choice-cut)(backtrack)))
    ,(check 'test-choice-get-set "Get and set CHO frame:"
	   `((cho-get ,arg1)(cho-set ,arg1)))
    ,(test 'test-assign "'() ASSIGN:"
	   `((assign () ,dialog-empty-lst)
	     (empty? ,dialog-empty-lst (jump passed))))
    ,(test 'test-make-var "Variable unification:"
	   `((make-var ,arg1)(make-var ,arg2)
	     (assign (num 2) ,arg1-unify)(assign (num 4) ,arg2-unify)
	     (not-unify? ,arg1 ,arg2 (jump passed))))
    ,(test 'test-make-pair "Pair unification:"
	    `((make-var ,arg1)(make-var ,arg2)
	      (make-pair ,arg1 ,arg2 (reg-store 2))
	      (assign (num 6) (reg 3))(assign (num 12) (reg 4))
	      (make-pair (reg 3) (reg 4) (reg-store 5))
	      (assign (reg 5) (reg-unify 2))
	      (not-unify? (num 6) ,arg1 backtrack)
	      (not-unify? (num 12) ,arg2 backtrack)
	      (unify? (reg 2) (reg 5) (jump passed))))
    ,(test 'test-aux-raw-push "Raw AUX push and pop:"
	   `((aux-raw-push (byte 0))(aux-list-pop ,arg1)
	     (empty? ,arg1 (jump passed))))
    ,(test 'test-aux-val-push "AUX push and pop:"
	   `((aux-raw-push (byte 0))(aux-val-push (num 5))
	     (aux-list-pop ,arg1)(make-var ,arg2)
	     (make-pair ,arg2 (reg 2) ,arg1-unify)
	     (unify? (num 5) ,arg2 (jump passed))))
    ,(test 'test-aux-list-chk-pop "AUX pop check:"
	   `((aux-raw-push (byte 0))(aux-val-push (num 10))
	     (aux-list-chk-pop (num 10))
	     (aux-raw-push (byte 0))
	     (choice-push (byte 0) (jump passed))
	     (aux-list-chk-pop (num 10))))
    ,(test 'test-aux-list-match-pop "AUX pop match:"
	   `((aux-raw-push (byte 0))
	     (aux-val-push (num 1))
	     (aux-val-push (num 2))
	     (aux-val-push (num 3))
	     (aux-list-match-pop (num 2))
	     (choice-push (byte 0) (jump passed))
	     (aux-raw-push (byte 0))(aux-list-match-pop (num 2))))
    ,(test 'test-list-split "List splitting:"
	   `((assign ((num 2) (num 3)) ,arg1)
	     (make-pair (num 1) ,arg1 (reg-store 1))
	     (list-split ,arg2 ,arg1 (reg 2))
	     (assign ((num 1)) (reg 3))
	     (unify? (reg 3) (reg 2) (jump passed))))
    ,(test 'test-stop "Stoppable choice point:"
	   '((stop-push (jump crash))(stop-pop)
	     (stop-push (jump passed))(stop)))
    ,(test 'test-store-word "Store and load word:"
	   `((store-word 0 (id 0) (word 16))
	     (load-word 0 (id 0) ,arg1)
	     (unify? (word 16) ,arg1 (jump passed))))
    ,(test 'test-store-byte "Store and load byte:"
	   `((store-byte 0 (id 15) (vbyte 8))
	     (load-byte 0 (id 15) ,arg1)
	     (unify? (vbyte 8) ,arg1 (jump passed))))
    ,(test 'test-store-val "Store and load value:"
	   `((store-val 0 (id 4) (num 12))
	     (load-val 0 (id 4) ,arg1)
	     (unify? (num 12) ,arg1 (jump passed))))
    ,(test 'test-flag-set "Set and reset object flags:"
	   '((flag-set 0 (id 15))(flag-reset 0 (id 15))
	     (flag? 0 (id 15) backtrack)
	     (flag-reset 0 (id 16))(flag-set 0 (id 16))
	     (flag? 0 (id 16) (jump passed))))
    ,(skip 'test-unlink "Unlink object field:")
    ,(check 'test-parent-set "Set object parent:"
	    '((parent-set (obj 1) 0)))
    ,(skip 'test-raw-eq? "Raw equality check:")
    ,(test 'test-bound? "Bounded variable check:"
	   `((make-var ,arg1)(bound? ,arg1 backtrack)
	     (assign (num 2) ,arg1-unify)
	     (bound? ,arg1 (jump passed))))
    ,(test 'test-empty? "Empty list check:"
	   `((assign (num 0) ,arg1)(empty? ,arg1 backtrack)
	     (assign ,dialog-empty-lst ,arg1)
	     (empty? ,arg1 (jump passed))))
    ,(test 'test-num? "Number check:"
	   `((assign (vbyte 42) ,arg1)(num? ,arg1 backtrack)
	     (assign (num 1) ,arg1)(num? ,arg1 (jump passed))))
    ,(test 'test-pair? "Pair check:"
	   `((assign (num 3) ,arg1)(pair? ,arg1 backtrack)
	     (make-pair (num 1) ,dialog-empty-lst-unify (reg-store 0))
	     (pair? ,arg1 (jump passed))))
    ,(test 'test-obj? "Object check:"
	   `((assign (obj 1) ,arg1)
	     (not-obj? ,arg1 backtrack)
	     (obj? ,arg1 (jump passed))))
    ,(test 'test-word? "Word check:"
	   `((assign (word 0) ,arg1)
	     (not-word? ,arg1 backtrack)
	     (word? ,arg1 (jump passed))))
    ,(skip 'test-uword? "Unrecognised word check:")
    ,(skip 'test-unify? "Unification check:")
    ,(test 'test-gt? "(a > b) check:"
	   '((not-gt? (num 2) (num 1) backtrack)
	     (gt? (num 2) (num 1) (jump passed))))
    ,(test 'test-eq? "Equality check:"
	   '((eq? (vbyte 1) (obj 1) (jump passed))))
    ,(skip 'test-mem-eq? "Memory equality check:")
    ,(skip 'test-flag? "Object flag check:")
    ,(test 'test-cwl? "CWL check:"
	   '((cwl? backtrack)
	     (cwl-inc)(not-cwl? backtrack)
	     (cwl-dec)(not-cwl? (jump passed))))
    ,(test 'test-num-add "Addition:"
	   `((num-add (num 2) (num 2) ,arg1)
	     (eq? (num 4) ,arg1 (jump passed))))
    ,(test 'test-num-sub "Subtraction:"
	   `((num-sub (num 12) (num 2) ,arg1)
	     (eq? (num 10) ,arg1 (jump passed))))
    ,(test 'test-num-mul "Multiplication:"
	   `((num-mul (num 4) (num 3) ,arg1)
	     (eq? (num 12) ,arg1 (jump passed))))
    ,(test 'test-num-div "Division:"
	   `((num-div (num 12) (num 6) ,arg1)
	     (eq? (num 2) ,arg1 (jump passed))))
    ,(test 'test-num-mod "Division remainder:"
	   `((num-mod (num 100) (num 25) ,arg1)
	     (eq? (num 0) ,arg1 (jump passed))))
    ,(test 'test-num-rand "Random number generation:"
	   `((num-rand (num 1) (num 10) ,arg1)
	     (not-gt? ,arg1 (num 0) backtrack)
	     (gt? (num 11) ,arg1 (jump passed))))
    ,(test 'test-num-inc "Number incrementation:"
	   `((num-inc (num 6) ,arg1)
	     (eq? (num 7) ,arg1 (jump passed))))
    ,(test 'test-num-dec "Number decrementation:"
	   `((num-dec (num 10) ,arg1)
	     (eq? (num 9) ,arg1 (jump passed))))
    ,(test 'test-raw-inc "Raw incrementation:"
	   `((raw-inc (vbyte 6) ,arg1)
	     (eq? (vbyte 7) ,arg1 (jump passed))))
    ,(test 'test-raw-dec "Raw decrementation:"
	   `((raw-dec (vbyte 5) ,arg1)
	     (eq? (vbyte 4) ,arg1 (jump passed))))
    ,(check 'test-print "Displaying text:"
	    '((print-val "check")(space)(print-val "below")(no-space)(line)
	      (print-a-str-a "The (fixed) serial is")(print-serial)(line)
	      (print-a-str-a "The quick brown fox jumps over the lazy dog,")(line)
	      (print-a-str-n "The dog thought the fox's exercise such a slog.")(line)
	      (print-n-str-a "While the fox trotted through the bog,")(line)
	      (print-n-str-n "The dog slept like a log.")(line)))
    ,(test 'test-choice-env "Persistent choicepoint environment:"
	   '((choice-push (byte 0) (jump crash))
	     (env-push (byte 1))(assign (num 2) (env 0))
	     (choice-push (byte 0) (jump crash))
	     (env-pop)(choice-pop (byte 0))
	     (eq? (num 2) (env 0) (jump reset-handler))))
    ,(test 'test-aux-car-cdr "AUX list splitting:"
	   `((aux-raw-push (byte 0))
	     (aux-val-push (vbyte 1))
	     (aux-val-push (vbyte 2))
	     (aux-list-pop ,arg1)
	     (make-pair ,arg2 (reg 2) ,arg1-unify)
	     (assign (reg 2) ,arg1)
	     (make-pair ,arg2 (reg 2) ,arg1-unify)
	     (empty? (reg 2) (jump passed))))
    ,(check 'test-word-compare "2-word comparison:"
	   '((idx-set "look")
	     (check-compare? "listen" "shout" backtrack)))
    ,(test 'test-tco "Tail-call optimisation: "
	   `((env-push (byte 0))(cont-set (jump tco-yes))(env-push (byte 2))
	     (assign (num 100) (env 0))
	     (jmp-tail (jump tco-loop))))
    (tco-loop
     (eq? (num 0) (env 0) (jump restore-cont))
     (assign ((num 1) (num 2) (num 3) (num 4) (num 5)) (env 1))
     (num-dec (env 0) (env 0))(jmp-tail (jump tco-loop)))
    (end (par))
    ,(info 'quit quittable? "Quitting the program..." 'interim)
    (exit (quit))
    (interim
     (print-a-str-a "(Unable to quit)")(line)
     (print-a-str-a "Dropping into sandbox...")(line))
    (sandbox
     (choice-pop-push (byte 0) (jump sandbox))
     (print-a-str-a "Type a message:")(line)
     (get-input ,arg1)
     (print-val ,arg1)(line)
     (backtrack))))
