(in-package :fwoar.cl-git)

;; TODO: Update the code so this uses an object instead of a path.
(defvar *git-repository*)
(setf (documentation '*git-repository* 'variable)
      "The git repository path for porcelain commands to operate on.")

(defvar *git-encoding* :utf-8
  "The encoding to use when parsing git objects")

(defun git:in-repository (root)
  (setf *git-repository*
        (truename root)))

(defmacro git:with-repository ((root) &body body)
  `(let ((*git-repository* (truename ,root)))
     ,@body))

(defun git:show-repository ()
  *git-repository*)

(defun in-git-package (symbol)
  (intern (symbol-name symbol)
          :git))

(defun handle-list (_1)
  (case (in-git-package (car _1))
    (git::unwrap `(uiop:nest (car)
                             (mapcar ,@(cdr _1))))
    (t (cons (in-git-package (car _1))
             (cdr _1)))))

(defmacro git:git (&rest commands)
  `(uiop:nest ,@(reverse
                 (mapcar (serapeum:op
                           (typecase _1
                             (string `(identity ,_1))
                             (list (handle-list _1))))
                         commands))))

(defun ensure-ref (thing &optional (repo (repository *git-repository*)))
  (typecase thing
    (git-ref thing)
    (t (ref repo thing))))

(defun git::ensure-ref (it)
  (ensure-ref it))

(defun git::<<= (fun &rest args)
  (apply #'mapcan fun args))

(defmacro git::map (fun list)
  (alexandria:once-only (list)
    (alexandria:with-gensyms (it)
      `(mapcar ,(if (consp fun)
                    `(lambda (,it)
                       (,(in-git-package (car fun))
                        ,@(cdr fun)
                        ,it))
                    `',(in-git-package fun))
               ,list))))

(defmacro git::juxt (&rest args)
  (let ((funs (butlast args))
        (arg (car (last args))))
    (alexandria:once-only (arg)
      `(list ,@(mapcar (lambda (f)
                         `(,@(alexandria:ensure-list f) ,arg))
                       funs)))))

(defmacro git::pipe (&rest funs)
  (let ((funs (reverse (butlast funs)))
        (var (car (last funs))))
    `(uiop:nest ,@(mapcar (lambda (it)
                            (if (consp it)
                                `(,(in-git-package (car it)) ,@(cdr it))
                                `(,(in-git-package it))))
                          funs)
                ,var)))

(defun git::filter (fun &rest args)
  (apply #'remove-if-not fun args))

(defun git::object (thing)
  (extract-object thing))

(defun git:show (object)
  (extract-object
   object))

(defun git:contents (object)
  (git:show object))

(defstruct (tree-entry (:type vector))
  te-name te-mode te-id)

(defun git:component (&rest args)
  (let ((component-list (butlast args))
        (target (car (last args))))
    (fwoar.cl-git::component component-list target)))

(defun git:tree (commit-object)
  (component :tree
             commit-object))

(defun git::filter-tree (name-pattern tree)
  #+lispworks
  (declare (notinline serapeum:string-prefix-p))
  (let* ((lines (fwoar.string-utils:split #\newline tree))
         (columns (map 'list
                       (serapeum:op
                         (coerce (fwoar.string-utils:split #\tab _)
                                 'simple-vector))
                       lines)))
    (remove-if-not (serapeum:op
                     (cl-ppcre:scan name-pattern _ ))
                   columns
                   :key #'tree-entry-te-name)))

(defun git:branch (&optional (branch :master))
  #+lispworks
  (declare (notinline serapeum:assocadr))
  (let ((branches (branches (repository *git-repository*))))
    (ref (repository *git-repository*)
         (serapeum:assocadr (etypecase branch
                              (string branch)
                              (keyword (string-downcase branch)))
                            branches
                            :test 'equal))))

(defun git:branches ()
  (branches (repository *git-repository*)))

(defun git::parents (commit)
  (alexandria:mappend 'cdr (component :parents commit)))
(defun git:commit-parents (commit)
  (git::parents commit))

;;; XXX: Should we use fset to return a set of results?
(defun git:rev-list (ref-id)
  (labels ((iterate (queue accum)
             (if (null queue)
                 accum
                 (iterate (append (cdr queue)
                                  (git::parents (ensure-ref (car queue))))
                   (cons ref-id accum)))))
    (iterate (list ref-id) ())))
