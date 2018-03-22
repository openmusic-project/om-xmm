
;; Lisp code for XMM / OM objects


(in-package :xmm)

(defclass xmmiae (om-cleanup-mixin data-stream)
((iae-obj :accessor iae-obj :initform nil)
 (markers-track :accessor markers)))


(defun test-xmm (entry)
  (print opennXMM))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;learn(list) :
;;list is a list of samples. 
;;each sample is a list of size 2 : the descriptor matrix, and the label
;;descriptor matrix is a list of 9 descriptor vectors
;;descriptor vector is a list of value 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun learn(list)
  (let ((laabels (fli:allocate-foreign-object :type :char :nelems (length list)))
        (descrs (fli:allocate-foreign-object :type :pointer :nelems (length list)))
        (sizes (fli:allocate-foreign-object :type :int :nelems (length list))))

    ;;Loop for each sample
    (loop for j from 0 to (1- (length list))
          do (let ((size (length (car (car (nth j list))))))
                 (setf (fli:dereference laabels :type :char :index j) (char (cadr (nth j list)) 0))
                 (setf (fli:dereference descrs :type :pointer :index j) (fli:allocate-foreign-object :type :pointer :nelems (length (car (nth j list)))))
                 (setf (fli:dereference sizes :type :int :index j) size)
               ;;Loop for each descriptor
               (loop for i from 0 to (1- (length (car (nth j list))))  
                     do (setf (fli:dereference (fli:dereference descrs :type :pointer :index j) :type :pointer :index i) 
                              (fli:allocate-foreign-object :type :float :nelems size :initial-contents (nth i (car (nth j list))))))))
    

    (code-char (trainXMM descrs (length list) sizes laabels))
;;FREE MEMORY
))

