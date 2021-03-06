;============================================================================
; OM-XMM
; A bridge between om7 and the XMM library.
;
; XMM is a C++ library that implements Gaussian Mixture Models and Hidden Markov Models for recognition and regression. 
; The library implements an interactive machine learning workflow with fast training and continuous, real-time inference. 
; See http://ircam-rnd.github.io/xmm/
;============================================================================
;
;   This program is free software. For information on usage 
;   and redistribution, see the "LICENSE" file in this distribution.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of   
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
;
;============================================================================


;; Lisp code for XMM / OM objects

(in-package :xmm)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;         XMM OBJECT       ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(om::defclass! xmm-model (om::om-cleanup-mixin)
  ((labls :accessor labls :initform nil :type list)
   (dataset :accessor dataset :initform nil :initarg :dataset :type list) ; DATASET = LIST de ((DATA1 LABEL1) (DATA2 LABEL2) ...)      
   (means :accessor means)
   (stddevs :accessor stddevs)
   (data-ptr :accessor data-ptr :initform nil) ; PTR on c++ Trainingset object 
   (model-ptr :accessor model-ptr :initform nil ) ; PTR on c++ HHMM object
   (errors :accessor errors :initform nil :type list) ;Number of errors per ground truth label (computed with the test function)
   (name :accessor name :initform (gensym "XMM-Model"))
   (states :accessor states :initform 10 :type integer)   ; Number of hidden states for the HHMM
   (gaussians :accessor gaussians :initform 1 :type integer) ; Number of gaussians per state (gaussian mixture models)
   (regularization :accessor regularization :initform (list 0.05 0.01) :type list) ;Relative and absolute regularization values for EM algorithm
   (normalize-data :accessor normalize-data :initform nil)
   (table-result :accessor table-result :initform '()) ;Number of errors for confusion matrix (computed with the test function)
   (dim :accessor dim :initform 0)
   )
  (:icon 1))


(defmethod om::om-cleanup ((self xmm-model))
  (when (model-ptr self)
    (om::om-print (format nil "deleting model of ~A (~A) [~A] and dataset [~A]" self (name self) (model-ptr self) (data-ptr self)) "GC")
    (if (and (not (fli::null-pointer-p (model-ptr self))) (not (fli::null-pointer-p (data-ptr self))))
        (xmm-free (model-ptr self) (data-ptr self)))
  ))

(defmethod initialize-instance ((self xmm-model) &rest initargs)
  (call-next-method)
  (setf (model-ptr self) (xmm-initmodel (first (regularization self)) (second (regularization self)) (states self) (gaussians self)))
  self)


#+om-sharp
(defmethod om::om-init-instance ((self xmm-model) &optional args)
  (call-next-method)
  (train-model self)
  self)

(defmethod om::additional-class-attributes ((self xmm-model)) 
  '(xmm::states xmm::gaussians xmm::regularization xmm::normalize-data))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;       TRAIN, RUN, TEST   ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmethod train-model ((self xmm-model))
  (if (dataset self)
      (progn 
        (om::om-print "init and train......" "XMM")
        (setf (data-ptr self) (xmm-initdata (setf (dim self) (length (caar (dataset self))))))
        (fill_data self)
        (xmm-train (data-ptr self) (model-ptr self))
        (om::om-print ".... done training !" "XMM"))
    (om::om-print "missing some data to learn.." "XMM")))




;;run : output a predicted label for unlabelled data
;;data is a matrix of descriptors for 1 sample 
;;descriptor matrix is a list of descriptor vectors
;;reset : if nil : the model's passed results will be kept, influencing the next results. else, model's results will be reset
(om::defmethod! run-model ((self xmm-model) data &optional (reset 1))
  (let ((descr (fli:allocate-foreign-object :type :pointer :nelems (length data)))
        (size (length (car data)))
        (resultptr (fli:allocate-foreign-object :type :char :nelems 20))
        (likelihood 0)
        (cur)
        (i 0)
        (result (make-string 20 :initial-element #\0)))
    (if (= 0 size) (om::om-print "Data size is null, frame might be too small" "XMM") 
      (if (not (= (length data) (dim self))) (om::om-print "Data must have the same dimension as the training data" "XMM") 
        (progn

          (if (normalize-data self)
          ;NORMALIZATION
              (setf data (car (normalize self (list data)))))

          ;;Loop for each descriptor, and build data in pointer to send to xmm
          (loop for i from 0 to (1- (length data))  
                do (setf (fli:dereference descr :type :pointer :index i) 
                         (fli:allocate-foreign-object :type :float :nelems size :initial-contents (to-float (nth i data)))))
          (setf likelihood (xmm-run descr size (dim self) (model-ptr self) reset resultptr))
          
          ;fetch result from pointer
          (setf cur (fli:dereference resultptr :type :char :index 0))
          (loop until (char= cur #\0) do
                (progn 
                  (setf (char result i) cur)
                  (incf i)
                  (setf cur (fli:dereference resultptr :type :char :index i))))
          (setf result (subseq result 0 i))
        ;free pointer
          (loop for i from 0 to (1- (length data))
                do (fli:free-foreign-object (fli:dereference descr :type :pointer :index i)))
          (fli:free-foreign-object descr)
          (fli:free-foreign-object resultptr)
          ;(if (< likelihood 0.6) (setf result "notsure"))
          (om::om-print (format nil "~a with ~f likelihood" result likelihood) "XMM")
          )))
    result)
)


;;test : outputs the accuracy for prediction on labelled data
;;fills errors list with number of error for each actual label
;;dataset is a list of samples
;;each sample is a list of 2 (desc-matrix , label) 
;;descriptor matrix is a list of descriptor vectors
(om::defmethod! test-model ((self xmm-model) dataset)
  (let ((accuracy 0)
        (num-samples (length dataset)))
            (setf (errors self) (make-list (length (labls self)) :initial-element 0))
     (setf (table-result self) (make-list (length (labls self)) :initial-element (make-list (length (labls self)) :initial-element 0)))
    (loop for sample in dataset
          do (let* ((pred (run-model self (car sample)))
                   (real (cadr sample))
                   (pos (position real (labls self) :test #'equal)))
               ;(print (format nil "pred: ~A " pred))
               ;(print (format nil " actual: ~A " real))
               (if (not pos) (progn (om::om-print (format nil "Label ~a was not in training..." real) "XMM")  
                               (decf num-samples))
                 (if (string= pred (make-string 20 :initial-element #\0)) (decf num-samples)  

                 (progn
                   ;(if (string= "notsure" pred)  (decf num-samples)
                     (if (string= pred real) 
                         (incf accuracy) 
                       (progn (incf (nth pos (errors self)))
                     ;(om::om-print (format nil "Predicted ~a instead of ~a on number ~d " pred real count) "XMM")
                         ));)  
                   ;MAJ TABLE-RESULT
                   (setf (nth pos (table-result self)) 
                         (substnth (1+ (nth (position  pred (labls self) :test #'equal) (nth pos (table-result self))))
                                   (position pred (labls self) :test #'equal)
                                   (nth pos (table-result self))))
                   )))
               ))
    
    (om::om-print (format nil "Accuracy : ~d/~d" accuracy num-samples) "XMM")
    (/ accuracy num-samples)
))



;;Builds the xmm trainingset object with the attibute (dataset) and stores it in data-ptr
(defmethod fill_data ((self xmm-model))
  (let* ((data (dataset self))
        (laabels (fli:allocate-foreign-object :type :pointer :nelems (length data)))
        (descrs (fli:allocate-foreign-object :type :pointer :nelems (length data)))
        (sizes (fli:allocate-foreign-object :type :int :nelems (length data))))       
    (if (null data) (return-from fill_data "empty data"))
    
    (if (normalize-data self)
        (progn
          (om::om-print "Normalizing..." "XMM")
       ;Compute mean and stddev
          (compute-norms self (car (om::mat-trans data)))

       ;Normalize the data 
          (setf data (om::mat-trans (list (normalize self (car (om::mat-trans data))) (cadr (om::mat-trans data)))))
          (om::om-print "...done" "XMM")))



 ;;store data in pointers to pass to xmm library
    ;;Loop for each sample
    (loop for j from 0 to (1- (length data))
          do (let ((size (length (car (car (nth j data))))))
               (setf (fli:dereference laabels :type :pointer :index j) 
                     (fli:allocate-foreign-object :type :char :nelems (length (cadr (nth j data))) :initial-contents  (to-chars (cadr (nth j data)))))
               ;maj list labels
               (if (not (find (cadr (nth j data)) (labls self) :test #'string-equal))  
                   (setf (labls self) (append (labls self) (cdr (nth j data)))))
               ;alloc
               (setf (fli:dereference descrs :type :pointer :index j) 
                       (fli:allocate-foreign-object :type :pointer :nelems (length (car (nth j data)))))
               (setf (fli:dereference sizes :type :int :index j) size)
               ;;Loop for each descriptor
               (loop for i from 0 to (1- (length (car (nth j data))))  
                     do(setf (fli:dereference (fli:dereference descrs :type :pointer :index j) :type :pointer :index i) 
                             (fli:allocate-foreign-object :type :float :nelems size :initial-contents (to-float (nth i (car (nth j data)))))))))
    ;send to xmm library
    (code-char (xmm-filldata descrs (length (dataset self)) sizes laabels (data-ptr self)))
    ;free pointers
    (fli:free-foreign-object sizes)
    (loop for i from 0 to (1- (length data))
          do (progn (loop for j from 0 to (1- (length (car (nth i data))))
                          do (fli:free-foreign-object (fli:dereference (fli:dereference descrs :type :pointer :index i) :type :pointer :index j)))
               (fli:free-foreign-object (fli:dereference descrs :type :pointer :index i))
               (fli:free-foreign-object (fli:dereference laabels :type :pointer :index i))))
    (fli:free-foreign-object descrs)
    (fli:free-foreign-object laabels)
))


;;;;;;;;;;;;;;;;;;;;;;;;
;;;                  ;;;
;;;   EXPORT/IMPORT  ;;;
;;;                  ;;;
;;;;;;;;;;;;;;;;;;;;;;;;


(om::defmethod! export-json ((self xmm-model) path)
  (let ((path-ptr (fli:allocate-foreign-object :type :char :nelems (length path) :initial-contents (coerce path 'list))))
  (xmm-save path-ptr  (model-ptr self))
  (fli::free-foreign-object path-ptr)
  (om::om-print (format nil "Saved model at ~A " path) "XMM")
))



(om::defmethod! import-json ((self xmm-model) path)
  (when path
    (let* ((path-ptr (fli:allocate-foreign-object :type :char :nelems (length path) :initial-contents (coerce path 'list)))
           (lablptr (fli:allocate-foreign-object :type :pointer :nelems 30))   ;;; /!\ 30 labels maximum
           (dim (xmm-import path-ptr (model-ptr self) lablptr))
           (temp (list))
           (id 1)
           (i 0)
           (ptr)
           (cur #\r))
      (if (= dim 0)   (om::om-print "Failed to load file, please try again" "XMM") 
        (progn
          (setf (labls self) (list))
          (setf (dim self) dim)
      ;read list of labels in lablptr
          (loop until (= id 0) do 
                (progn 
                  (setf temp (list))
                  (setf id 0)
                  (setf ptr (fli:dereference lablptr :type :pointer :index i))
                  (setf cur (fli:dereference ptr :type :char :index 0))
                  (loop until (char= cur #\0) do
                        (progn
                          (setf temp (append temp (list cur)))
                          (setf id (1+ id))
                          (setf cur (fli::dereference ptr :type :char :index id))
                          ))
                  (if temp
                      (setf (labls self) (append (labls self) (list (concatenate 'string temp)))))
                  (print temp)
                  (setf i (1+ i))
                  (fli:free-foreign-object ptr)
                  ))
          (fli:free-foreign-object lablptr)
          (fli:free-foreign-object path-ptr)
          "Import done."
)))))



;;;;;;;;;;;;;;;;;;;;;;;;
;;;                  ;;;
;;;      GETTERS     ;;;
;;;                  ;;;
;;;;;;;;;;;;;;;;;;;;;;;;



(defmethod get-class-avrg ((self xmm-model) label)
  (if (dataset self)
      (let* ((result (fli:allocate-foreign-object :type :pointer :nelems (dim self)))
             (labelptr (fli:allocate-foreign-object :type :char :nelems (length label) :initial-contents (coerce label 'list))) 
             (size  (xmm-classavrg (data-ptr self) labelptr result))
             (ret (make-list (dim self)))
             (ptr))
        (loop for dim from 0 to (1- (dim self)) do
              (progn 
                (setf (nth dim ret)  (make-list size))
                (setf ptr (fli:dereference result :type :pointer :index dim))
                (loop for id from 0 to (1- size) do
                      (setf (nth id (nth dim ret)) (fli:dereference ptr :type :float :index id))
                      )
                (fli:free-foreign-object ptr)
                )
              )
        (fli:free-foreign-object labelptr)
        (fli:free-foreign-object  result)
        ret)
    (print "A dataset is needed to get a class avrg"))
)



(defmethod get-labels ((self xmm-model))
  (labls self)
)

(defmethod get-model ((self xmm-model))
  (model-ptr self)
)


(om::defmethod! get-confusion-matrix ((self xmm-model))
(if (null (table-result self)) (print "Please call the test function first")
(let* ((table (copy-list (table-result self)))
      (labls (labls self))
      (fieldnames (append (loop for line in table collect (write-to-string (reduce '+ line))) (list " "))))

  ;NORMALIZE
  (setf table
        (loop for line in (table-result self) collect 
              (loop for item in line collect 
                        (float (if (not (= 0 (reduce '+ line))) (/ item (reduce '+ line)) 0 )) ))) 
  ;BUILD 2D-ARRAY
  (make-instance 'om::2D-array
   :data 
   (append (loop for i from 0 to (1- (length table)) collect
                 (append (list (nth i labls)) 
                         (loop for j in (nth i table) collect
                               (if (= 0 j) " " (format nil "~2$" j))) 
                         (list " ")))
         (list (append (list " ") labls (list " "))))
   :field-names fieldnames
)
))
)


(om::defmethod! get-errors ((self xmm-model))
  (loop for i from 0 to (1- (length (labls self)))
       do (print (format nil "~A ~d" (nth i (labls self)) (nth i (errors self))))
))


;;;;;;;;;;;;
;;; VIEW ;;;
;;;;;;;;;;;;

(defmethod om::display-modes-for-object ((self xmm-model))
  '(:hidden :text :mini-view))

#+om-sharp
(defmethod om::draw-mini-view ((self xmm-model) (box t) x y w h &optional time)
    (om::om-with-font 
     (om::om-def-font :font1 :size 10)
     (om::om-draw-string (+ x 10) (+ y 20) (concatenate 'string "Labels : " (format nil "~{~A~^,~}" (labls self))) :wrap (om::box-w box))
     (om::om-draw-string (+ x 10) (+ y 40) (concatenate 'string "Dataset of " (format nil "~d samples" (length (dataset self)))) :wrap (om::box-w box))
))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                    ;;;
;;;    GENETIC ALGO FOR HYPER-PARAMETER OPTIMIZATION   ;;;
;;;                                                    ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;; PARAM format : ("descriptor"   (5 8 7 4 6 8)       15            2              (0.1 0.05))
;;                 pipo module   descr  to keep   states_num    gaussians      regularization

(defun gene-algo (fun firstparams descnum &optional (numchildren 4)) 
  (let* ((params firstparams)
         (condition T)) 
    (loop while condition do
          ;(progn 
            (setf params (reproduce
                        ;Get 4 best results (( "descr" 10 (0.05 0.01)) (0.3457 0.7575)) 
                               (print (find4best
                                ;;collect results
                                (loop for param in params collect 
                                      (if (not (= (length param) 2)) 
                                          (funcall fun (print param))
                                        ;(funcall fun (car (print param)))
                                        (print param)
                                        )
                                      ))) descnum numchildren))
   ;Terminating condition      
   ;(if (< 0.9 (car (second (car params)))) (setf condition nil)))
    ))
)

(defun reproduce (results descnum numchildren) 
  (let* ((ret)
         (vardesc)
         (varreg1)
         (varreg2)
         (newgaus)
        (parents (car (om:mat-trans results))))
    (loop for i from 1 to numchildren do
    (loop for parent in parents do 
          (setf ret 
                (append ret 
                        ;Create new child with random variation on descr kept
                        (list (list  (car parent) (if (not (find (setf vardesc (random descnum)) (second parent))) 
                                                      (append (second parent) (list vardesc)) 
                                                    (if (> (length (second parent)) 1) (remove vardesc (second parent)) (second parent)))
                                     ;variation on number of states
                                     (+ (- 4 (random 9)) (third parent))
                                     ;variation on number of gaussians per states
                                     (if (> (setf newgaus (+ (- 1 (random 3)) (fourth parent))) 0) newgaus (fourth parent))
                                     
                                     ;variation on regularization
                                     ;(fourth parent)
                                     (list (if (< 0 (setf varreg1 (+ (/ (- 2 (random 5)) 100) (car (fifth parent))))) varreg1 (car (fifth parent)))  
                                           (if (< 0 (setf varreg2 (+ (/ (- 2 (random 5)) 100) (cadr (fifth parent))))) varreg2 (cadr (fifth parent))) ) 
                                     ))
                        )))  )
    ret)
)

(defun testaccu (item1 item2)
  (if  item1
      (if (> (mean (second item1)) (mean (second item2)))
          item1
        item2)
   item2)
)


(defun find4best (results)
  (if (> (length results) 4) 
      (let ((ret (make-list 4))
            (mlist results))
        (loop for i from 0 to 3 do 
              (let ((max nil))
                (loop for item in mlist do 
                      (if (not (find item ret)) (setf max (testaccu max item)))
                      )
                (setf mlist (remove max mlist))
                (setf (nth i ret) max)
                ))
        ret
        )
    results)
)



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;                          ;;;;;
;;;;;      NORMALISATION       ;;;;;
;;;;;                          ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmethod normalize ((self xmm-model) data)
  (let ((descnum (length (car data))))
  (loop for sample in data collect
        (loop for idesc from 0 to (1- descnum) collect
              (loop for n in (nth idesc sample) collect
                    (normfun n (nth idesc (means self)) (nth idesc (stddevs self)))
              )
        )
  )
  )
)



(defmethod compute-norms ((self xmm-model) data)
  (let ((numdesc (length (car data))))
    (setf (means self) (make-list numdesc))
    (setf (stddevs self) (make-list numdesc))
    (loop for i from 0 to (1- numdesc) do
        (progn
          (setf (nth i (means self)) (mean (apply #'append (nth i (om::mat-trans data)))))
          (setf (nth i (stddevs self)) (stdev (apply #'append (nth i (om::mat-trans data)))))
          ))
)
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;         SIDE TOOLS       ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun normfun (x mean std)
  (/ (- x mean) std)
)

(defun stdev (x)
  (let ((m (mean x)))
  (sqrt (/ (reduce '+ (mapcar (lambda (a) (expt (- a m) 2)) x))
           (length x)))
))

(defun mean(lst)
  (/ (reduce '+ lst) (length lst)))

(defun to-float (list)
  (loop for elem in list collect
        (float elem)
))

(defun to-chars (str)
  (loop for i from 0 to (1- (length str)) collect
        (char str i)
))

(defun substnth ( a n l )
    (if l
        (if (zerop n)
            (cons a (cdr l))
            (cons (car l) (substnth a (1- n) (cdr l)))
        ))
)



