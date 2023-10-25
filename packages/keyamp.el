;;; keyamp.el --- Key Amplifier -*- coding: utf-8; lexical-binding: t; -*-

;; Author: Egor Maltsev <x0o1@ya.ru>
;; Version: 1.0 2023-09-13

;;      _                   _
;;    _|_|_               _|_|_
;;   |_|_|_|             |_|_|_|
;;           _ _     _ _
;;          | | |   | | |
;;          |_|_|   |_|_|

;; This package is part of input model.
;; Follow the link: https://github.com/xEgorka/keyamp

;;; Commentary:

;; Keyamp provides 3 modes: insert, command and repeat. Command mode
;; based on persistent transient keymap.

;; Repeat mode pushes transient remaps to keymap stack on top of
;; command mode for easy repeat of commands chains during screen
;; positioning, cursor move and editing. Point color indicates
;; transient remap is active. ESDF and IJKL are mostly used, DEL/ESC
;; and RET/SPC control EVERYTHING. Home row and thumb cluster only.

;; DEL and SPC are two leader keys, RET activates insert mode, ESC for
;; command one. Holding down each of the keys posts control sequence
;; depending on mode. Keyboard has SYMMETRIC layout: left side for
;; editing, «No» and «Escape» while right side for moving, «Yes» and
;; «Enter». Any Emacs major or minor mode could be remaped to fit the
;; model, find examples in the package.

;; Karabiner integration allows to post control or leader sequences by
;; holding down a key. NO need to have any modifier or arrows keys at
;; ALL. Holding down posts leader layer. The same symmetric layout
;; might be configured on ANSI keyboard, ergonomic split and virtual
;; keyboards. See the link for layouts and karabiner config.

;;; Code:



(defgroup keyamp nil
  "Customization options for keyamp"
  :group 'help
  :prefix "keyamp-")

(defvar keyamp-command-hook nil "Hook for `keyamp-command'")
(defvar keyamp-insert-hook  nil "Hook for `keyamp-insert'")

(defconst keyamp-karabiner-cli
  "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
  "Karabiner-Elements CLI executable")

(defconst keyamp-command-indicator "🟢" "Character indicating command mode is active.")
(defconst keyamp-insert-indicator  "🟠" "Character indicating insert mode is active.")
(defconst keyamp-repeat-indicator  "🔵" "Character indicating repeat mode is active.")

(defconst keyamp-command-cursor "lawngreen"
  "Cursor color indicating command mode is active.")
(defconst keyamp-insert-cursor  "gold"
  "Cursor color indicating insert mode is active.")
(defconst keyamp-repeat-cursor "deepskyblue"
  "Cursor color indicating repeat mode is active.")

(defconst keyamp-idle-timeout 120 "Modes timeout.")


;; layout lookup tables for key conversion

(defvar keyamp-layouts nil "A alist. Key is layout name, string type.
Value is a alist, each element is of the form (\"e\" . \"d\").
First char is qwerty, second is corresponding char of the destination layout.
When a char is not in this alist, they are assumed to be the same.")

(push '("qwerty" . nil) keyamp-layouts)

(push
 '("engineer-engram" .
   (("-" . "#") ("=" . "%") ("`" . "`")  ("q" . "b") ("w" . "y") ("e" . "o")
    ("r" . "u") ("t" . "'") ("y" . "\"") ("u" . "l") ("i" . "d") ("o" . "w")
    ("p" . "v") ("[" . "z") ("]" . "{")  ("a" . "c") ("s" . "i") ("d" . "e")
    ("f" . "a") ("g" . ",") ("h" . ".")  ("j" . "h") ("k" . "t") ("l" . "s")
    (";" . "n") ("'" . "q") ("\\" . "}") ("z" . "g") ("x" . "x") ("c" . "j")
    ("v" . "k") ("b" . "-") ("n" . "?")  ("m" . "r") ("," . "m") ("." . "f")
    ("/" . "p") ("_" . "|") ("+" . "^")  ("~" . "~") ("Q" . "B") ("W" . "Y")
    ("E" . "O") ("R" . "U") ("T" . "(")  ("Y" . ")") ("U" . "L") ("I" . "D")
    ("O" . "W") ("P" . "V") ("{" . "Z")  ("}" . "[") ("A" . "C") ("S" . "I")
    ("D" . "E") ("F" . "A") ("G" . ";")  ("H" . ":") ("J" . "H") ("K" . "T")
    ("L" . "S") (":" . "N") ("\"" . "Q") ("|" . "]") ("Z" . "G") ("X" . "X")
    ("C" . "J") ("V" . "K") ("B" . "_")  ("N" . "!") ("M" . "R") ("<" . "M")
    (">" . "F") ("?" . "P") ("1" . "7")  ("2" . "5") ("3" . "1") ("4" . "3")
    ("5" . "9") ("6" . "8") ("7" . "2")  ("8" . "0") ("9" . "4") ("0" . "6")
    ("!" . "@") ("@" . "&") ("#" . "/")  ("$" . "$") ("%" . "<") ("^" . ">")
    ("&" . "*") ("*" . "=") ("(" . "+")  (")" . "\\"))) keyamp-layouts)

(defvar keyamp-current-layout "engineer-engram"
  "The current keyboard layout. Value is a key in `keyamp-layouts'.")

(defvar keyamp--convert-table nil
  "A alist that's the conversion table from qwerty to current layout.
Value structure is one of the key's value of `keyamp-layouts'.
Value is programtically set from value of `keyamp-current-layout'.
Do not manually set this variable.")

(setq keyamp--convert-table
      (cdr (assoc keyamp-current-layout keyamp-layouts)))

(defun keyamp--convert-kbd-str (Charstr)
  "Return the corresponding char Charstr according to
`keyamp--convert-table'. Charstr must be a string that is the argument
to `kbd'. E.g. \"a\" and \"a b c\". Each space separated token is
converted according to `keyamp--convert-table'."
  (interactive)
  (mapconcat
   'identity
   (mapcar
    (lambda (x)
      (let ((xresult (assoc x keyamp--convert-table)))
        (if xresult (cdr xresult) x)))
    (split-string Charstr " +"))
   " "))

(defmacro keyamp--define-keys (KeymapName KeyCmdAlist &optional Direct-p)
  "Map `define-key' over a alist KeyCmdAlist, with key layout remap.
The key is remapped from qwerty to the current keyboard layout by
`keyamp--convert-kbd-str'.
If Direct-p is t, do not remap key to current keyboard layout.

Example usage:
(keyamp--define-keys
 (define-prefix-command \\='xyz-map)
 \\='(
   (\"h\" . highlight-symbol-at-point)
   (\".\" . isearch-forward-symbol-at-point)
   (\"w\" . isearch-forward-word)))"
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       ,@(mapcar
          (lambda (xpair)
            `(define-key
               ,xkeymapName
               (kbd (,(if Direct-p #'identity #'keyamp--convert-kbd-str) ,(car xpair)))
               ,(list 'quote (cdr xpair))))
          (cadr KeyCmdAlist)))))

(defalias 'keyamp--dfk 'keyamp--define-keys)

(defmacro keyamp--define-keys-translation (KeyKeyAlist State-p)
  "Map `define-key' for `key-translation-map' over a alist KeyKeyAlist.
If State-p is nil, remove the mapping."
  (let ((xstate (make-symbol "keyboard-state")))
    `(let ((,xstate ,State-p))
       ,@(mapcar
          (lambda (xpair)
            `(define-key key-translation-map
               (kbd ,(car xpair))
               (if ,xstate (kbd ,(cdr xpair)) nil)))
          (cadr KeyKeyAlist)))))

(defmacro keyamp--define-keys-remap (KeymapName CmdCmdAlist)
  "Map `define-key' remap over a alist CmdCmdAlist."
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       ,@(mapcar
          (lambda (xpair)
            `(define-key
               ,xkeymapName
               [remap ,(list (car xpair))]
               ,(list 'quote (cdr xpair))))
          (cadr CmdCmdAlist)))))

(defalias 'keyamp--dkr 'keyamp--define-keys-remap)

(defmacro keyamp--set-transient-map (KeymapName CmdList)
  "Map `set-transient-map' using `advice-add' over a list CmdList."
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       ,@(mapcar
          (lambda (xcmd)
            `(advice-add ,(list 'quote xcmd) :after
                         (lambda (&rest r) "Repeat."
                           (set-transient-map ,xkeymapName))))
          (cadr CmdList)))))

(defalias 'keyamp--stm 'keyamp--set-transient-map)

(defmacro keyamp--set-transient-map-hook (KeymapName HookList)
  "Map `set-transient-map' using `add-hook' over a list HookList."
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       ,@(mapcar
          (lambda (xhook)
            `(add-hook ,(list 'quote xhook)
                         (lambda () "Repeat."
                           (set-transient-map ,xkeymapName)
                           (setq this-command 'next-line))))
          (cadr HookList)))))

(defalias 'keyamp--sth 'keyamp--set-transient-map-hook)

(defmacro keyamp--define-leader-keys (KeymapName CmdCons)
  "Map leader keys using `keyamp--define-keys'."
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       (keyamp--define-keys
        ,xkeymapName
        '(("DEL" . ,(car (cadr CmdCons))) ("<backspace>" . ,(car (cadr CmdCons)))
          ("SPC" . ,(cdr (cadr CmdCons))))))))

(defalias 'keyamp--dlk 'keyamp--define-leader-keys)



(defconst keyamp-engineer-engram-to-russian-computer
  '(("a" . "а") ("b" . "й") ("c" . "ф") ("d" . "ш") ("e" . "в")
    ("f" . "ю") ("g" . "я") ("h" . "о") ("i" . "ы") ("j" . "с")
    ("k" . "м") ("l" . "г") ("m" . "б") ("n" . "ж") ("o" . "у")
    ("q" . "э") ("r" . "ь") ("s" . "д") ("t" . "л") ("u" . "к")
    ("v" . "з") ("w" . "щ") ("x" . "ч") ("y" . "ц") ("z" . "х")
    ("." . "р") ("?" . "т") ("-" . "и") ("," . "п") ("'" . "е")
    ("`" . "ё") ("{" . "ъ") ("\"" . "н"))
  "Mapping for `keyamp-define-input-source'")

(defun keyamp-quail-get-translation (from)
  "Get translation Engineer Engram to russian-computer.
From character to character code."
  (interactive)
  (let ((to (alist-get from keyamp-engineer-engram-to-russian-computer
             nil nil 'string-equal)))
    (when (stringp to)
      (string-to-char to))))

(defun keyamp-define-input-source (input-method)
  "Build reverse mapping for `input-method'.
Use Russian input source for command mode. Respects Engineer Engram layout."
  (interactive
   (list (read-input-method-name "Use input method (default current): ")))
  (if (and input-method (symbolp input-method))
      (setq input-method (symbol-name input-method)))
  (let ((current current-input-method)
        (modifiers '(nil (control))))
    (when input-method
      (activate-input-method input-method))
    (when (and current-input-method quail-keyboard-layout)
      (dolist (map (cdr (quail-map)))
        (let* ((to (car map))
               (from (if (string-equal keyamp-current-layout "engineer-engram")
                         (keyamp-quail-get-translation (char-to-string to))
                       (quail-get-translation (cadr map) (char-to-string to) 1))))
          (when (and (characterp from) (characterp to))
            (dolist (mod modifiers)
              (define-key local-function-key-map
                (vector (append mod (list from)))
                (vector (append mod (list to)))))))))
    (when input-method
      (activate-input-method current))))



(defconst quail-keyboard-layout-engineer-engram
  "\
                              \
  7@5&1/3$9<8>2*0=4+6\\#|%^`~  \
  bByYoOuU'(\")lLdDwWvVzZ{[    \
  cCiIeEaA,;.:hHtTsSnNqQ}]    \
  gGxXjJkK-_?!rRmMfFpP        \
                              "
  "Engineer Engram keyboard layout for Quail, e.g. for input method.")

(require 'quail)
(push (cons "engineer-engram" quail-keyboard-layout-engineer-engram)
      quail-keyboard-layout-alist)

(defun keyamp-qwerty-to-engineer-engram ()
  "Toggle translate qwerty layout to engineer engram on Emacs level.
Useful when Engineer Engram layout not available on OS or keyboard level."
  (interactive)
  (if (get 'keyamp-qwerty-to-engineer-engram 'state)
      (progn
        (put 'keyamp-qwerty-to-engineer-engram 'state nil)
        (quail-set-keyboard-layout "standard")
        (message "Translation deactivated"))
    (progn
      (put 'keyamp-qwerty-to-engineer-engram 'state t)
      (quail-set-keyboard-layout "engineer-engram")
      (message "Translation activated")))
  (let ()
    (keyamp--define-keys-translation
     '(("-" . "#") ("=" . "%") ("`" . "`")  ("q" . "b") ("w" . "y") ("e" . "o")
       ("r" . "u") ("t" . "'") ("y" . "\"") ("u" . "l") ("i" . "d") ("o" . "w")
       ("p" . "v") ("[" . "z") ("]" . "{")  ("a" . "c") ("s" . "i") ("d" . "e")
       ("f" . "a") ("g" . ",") ("h" . ".")  ("j" . "h") ("k" . "t") ("l" . "s")
       (";" . "n") ("'" . "q") ("\\" . "}") ("z" . "g") ("x" . "x") ("c" . "j")
       ("v" . "k") ("b" . "-") ("n" . "?")  ("m" . "r") ("," . "m") ("." . "f")
       ("/" . "p") ("_" . "|") ("+" . "^")  ("~" . "~") ("Q" . "B") ("W" . "Y")
       ("E" . "O") ("R" . "U") ("T" . "(")  ("Y" . ")") ("U" . "L") ("I" . "D")
       ("O" . "W") ("P" . "V") ("{" . "Z")  ("}" . "[") ("A" . "C") ("S" . "I")
       ("D" . "E") ("F" . "A") ("G" . ";")  ("H" . ":") ("J" . "H") ("K" . "T")
       ("L" . "S") (":" . "N") ("\"" . "Q") ("|" . "]") ("Z" . "G") ("X" . "X")
       ("C" . "J") ("V" . "K") ("B" . "_")  ("N" . "!") ("M" . "R") ("<" . "M")
       (">" . "F") ("?" . "P") ("1" . "7")  ("2" . "5") ("3" . "1") ("4" . "3")
       ("5" . "9") ("6" . "8") ("7" . "2")  ("8" . "0") ("9" . "4") ("0" . "6")
       ("!" . "@") ("@" . "&") ("#" . "/")  ("$" . "$") ("%" . "<") ("^" . ">")
       ("&" . "*") ("*" . "=") ("(" . "+")  (")" . "\\"))
     (get 'keyamp-qwerty-to-engineer-engram 'state))))


;; keymaps

(defvar keyamp-map (make-sparse-keymap)
  "Parent keymap of `keyamp-command-map'.
Define keys that are available in both command and insert modes here.")

(defvar keyamp-command-map (cons 'keymap keyamp-map)
  "Keymap that takes precedence over all other keymaps in command mode.
Inherits bindings from `keyamp-map'.

In command mode, if no binding is found in this map
`keyamp-map' is checked, then if there is still no binding,
the other active keymaps are checked like normal. However, if a key is
explicitly bound to nil in this map, it will not be looked up in
`keyamp-map' and lookup will skip directly to the normally
active maps.

In this way, bindings in `keyamp-map' can be disabled by this map.
Effectively, this map takes precedence over all others when command mode
is enabled.")

(defvar keyamp--deactivate-command-mode-func nil)

(defvar keyamp-repeat-commands-hash nil
  "Hash table with commands which set transient keymaps.")



(progn
  (defconst keyamp-tty-seq-timeout 30
    "Timeout in ms to wait sequence after ESC sent in tty.")

  (defun keyamp-tty-ESC-filter (map)
    (if (and (equal (this-single-command-keys) [?\e])
             (sit-for (/ keyamp-tty-seq-timeout 1000.0)))
        [escape] map))

  (defun keyamp-lookup-key (map key)
    (catch 'found
      (map-keymap (lambda (k b) (if (equal key k) (throw 'found b))) map)))

  (defun keyamp-catch-tty-ESC ()
    "Setup key mappings of current terminal to turn a tty's ESC into <escape>."
    (when (memq (terminal-live-p (frame-terminal)) '(t pc))
      (let ((esc-binding (keyamp-lookup-key input-decode-map ?\e)))
        (define-key input-decode-map
          [?\e] `(menu-item "" ,esc-binding :filter keyamp-tty-ESC-filter)))))

  (define-key key-translation-map (kbd "ESC") (kbd "<escape>")))


;; setting keys

(keyamp--dfk
 keyamp-map
 '(("<escape>" . keyamp-escape)      ("S-<escape>" . ignore)
   ("C-^" . keyamp-left-leader-map)  ("C-+" . keyamp-left-leader-map)
   ("C-_" . keyamp-right-leader-map) ("C-И" . keyamp-right-leader-map)))

(keyamp--dfk
 keyamp-command-map
 '(("RET" . keyamp-insert)           ("<return>"    . keyamp-insert)          ("S-<return>"    . ignore)
   ("DEL" . keyamp-left-leader-map)  ("<backspace>" . keyamp-left-leader-map) ("S-<backspace>" . ignore)
   ("SPC" . keyamp-right-leader-map)

   ;; left half
   ("`" . delete-forward-char)          ("ё" . delete-forward-char)        ("~" . keyamp-qwerty-to-engineer-engram) ("Ë" . keyamp-qwerty-to-engineer-engram)
   ("1" . kmacro-play)                                                     ("!" . ignore)
   ("2" . kmacro-helper)                                                   ("@" . ignore)
   ("3" . kmacro-record)                                                   ("#" . ignore) ("№" . ignore)
   ("4" . append-to-register-1)                                            ("$" . ignore)
   ("5" . repeat)                                                          ("%" . ignore)

   ("q" . insert-space-before)          ("й" . insert-space-before)        ("Q" . ignore) ("Й" . ignore)
   ("w" . backward-kill-word)           ("ц" . backward-kill-word)         ("W" . ignore) ("Ц" . ignore)
   ("e" . undo)                         ("у" . undo)                       ("E" . ignore) ("У" . ignore)
   ("r" . kill-word)                    ("к" . kill-word)                  ("R" . ignore) ("К" . ignore)
   ("t" . cut-text-block)               ("е" . cut-text-block)             ("T" . ignore) ("Е" . ignore)

   ("a" . shrink-whitespaces)           ("ф" . shrink-whitespaces)         ("A" . ignore) ("Ф" . ignore)
   ("s" . open-line)                    ("ы" . open-line)                  ("S" . ignore) ("Ы" . ignore)
   ("d" . delete-backward)              ("в" . delete-backward)            ("D" . ignore) ("В" . ignore)
   ("f" . newline)                      ("а" . newline)                    ("F" . ignore) ("А" . ignore)
   ("g" . mark-mode)                    ("п" . mark-mode)                  ("G" . ignore) ("П" . ignore)

   ("z" . toggle-comment)               ("я" . toggle-comment)             ("Z" . ignore) ("Я" . ignore)
   ("x" . cut-line-or-selection)        ("ч" . cut-line-or-selection)      ("X" . ignore) ("Ч" . ignore)
   ("c" . copy-line-or-selection)       ("с" . copy-line-or-selection)     ("C" . ignore) ("С" . ignore)
   ("v" . paste-or-paste-previous)      ("м" . paste-or-paste-previous)    ("V" . ignore) ("М" . ignore)
   ("b" . toggle-letter-case)           ("и" . toggle-letter-case)         ("B" . ignore) ("И" . ignore)

   ;; right half
   ("6" . pass)                                                            ("^" . ignore)
   ("7" . number-to-register)                                              ("&" . ignore)
   ("8" . copy-to-register)                                                ("*" . goto-matching-bracket) ; qwerty「*」→「=」engram, qwerty「/」→「=」ru pc karabiner
   ("9" . eperiodic)                                                       ("(" . ignore)
   ("0" . terminal)                                                        (")" . ignore)
   ("-" . tetris)                                                          ("_" . ignore)
   ("=" . goto-matching-bracket)                                           ("+" . ignore)

   ("y"  . search-current-word)         ("н" . search-current-word)        ("Y" . ignore) ("Н" . ignore)
   ("u"  . backward-word)               ("г" . backward-word)              ("U" . ignore) ("Г" . ignore)
   ("i"  . previous-line)               ("ш" . previous-line)              ("I" . ignore) ("Ш" . ignore)
   ("o"  . forward-word)                ("щ" . forward-word)               ("O" . ignore) ("Щ" . ignore)
   ("p"  . exchange-point-and-mark)     ("з" . exchange-point-and-mark)    ("P" . ignore) ("З" . ignore)
   ("["  . other-frame)                 ("х" . other-frame)                ("{" . ignore) ("Х" . ignore)
   ("]"  . find-file)                   ("ъ" . find-file)                  ("}" . ignore) ("Ъ" . ignore)
   ("\\" . bookmark-set)                                                   ("|" . ignore)

   ("h" . beginning-of-line-or-block)   ("р" . beginning-of-line-or-block) ("H"  . ignore) ("Р" . ignore)
   ("j" . backward-char)                ("о" . backward-char)              ("J"  . ignore) ("О" . ignore)
   ("k" . next-line)                    ("л" . next-line)                  ("K"  . ignore) ("Л" . ignore)
   ("l" . forward-char)                 ("д" . forward-char)               ("L"  . ignore) ("Д" . ignore)
   (";" . end-of-line-or-block)         ("ж" . end-of-line-or-block)       (":"  . ignore) ("Ж" . ignore)
   ("'" . alternate-buffer)             ("э" . alternate-buffer)           ("\"" . ignore) ("Э" . ignore)

   ("n" . isearch-forward)              ("т" . isearch-forward)            ("N" . ignore) ("Т" . ignore)
   ("m" . backward-left-bracket)        ("ь" . backward-left-bracket)      ("M" . ignore) ("Ь" . ignore)
   ("," . next-window-or-frame)         ("б" . next-window-or-frame)       ("<" . ignore) ("Б" . ignore)
   ("." . forward-right-bracket)        ("ю" . forward-right-bracket)      (">" . ignore) ("Ю" . ignore)
   ("/" . goto-matching-bracket)                                           ("?" . ignore)

   ("<up>"   . up-line)   ("<down>"  . down-line)
   ("<left>" . left-char) ("<right>" . right-char)))

(keyamp--dfk
 (define-prefix-command 'keyamp-left-leader-map)
 '(("SPC" . select-text-in-quote)
   ("DEL" . select-block)             ("<backspace>" . select-block)
   ("RET" . execute-extended-command) ("<return>"    . execute-extended-command)
   ("TAB" . toggle-ibuffer)           ("<tab>"       . toggle-ibuffer)
   ("ESC" . ignore)                   ("<escape>"    . ignore)

   ;; left leader left half
   ("`" . ignore)
   ("1" . apply-macro-to-region-lines)
   ("2" . kmacro-name-last-macro)
   ("3" . ignore)
   ("4" . clear-register-1)
   ("5" . repeat-complex-command)

   ("q" . reformat-lines)
   ("w" . org-ctrl-c-ctrl-c)
   ("e" . split-window-below)
   ("r" . query-replace)
   ("t" . kill-line)

   ("a" . delete-window)
   ("s" . previous-user-buffer)
   ("d" . delete-other-windows)
   ("f" . next-user-buffer)
   ("g" . rectangle-mark-mode)

   ("z" . universal-argument)
   ("x" . save-buffers-kill-terminal)
   ("c" . copy-to-register-1)
   ("v" . paste-from-register-1)
   ("b" . toggle-previous-letter-case)

   ;; left leader right half
   ("6" . ignore)
   ("7" . jump-to-register)
   ("8" . ignore)
   ("9" . ignore)
   ("0" . ignore)
   ("-" . ignore)
   ("=" . ignore)
   ("y" . find-name-dired)
   ("u" . switch-to-buffer)

   ("i e" . flyspell-buffer)               ("i i" . show-in-desktop)
   ("i f" . count-words)                   ("i j" . set-buffer-file-coding-system)
   ("i s" . count-matches)                 ("i l" . revert-buffer-with-coding-system)

   ("o"  . bookmark-jump)
   ("p"  . view-echo-area-messages)
   ("["  . screenshot)
   ("]"  . rename-visited-file)
   ("\\" . bookmark-rename)
   ("h"  . recentf-open-files)

   ("j e" . global-hl-line-mode)           ("j i" . abbrev-mode)
   ("j s" . display-line-numbers-mode)     ("j l" . narrow-to-region-or-block)
   ("j d" . whitespace-mode)               ("j k" . narrow-to-defun)
   ("j f" . toggle-case-fold-search)       ("j j" . widen)
   ("j g" . toggle-word-wrap)              ("j h" . narrow-to-page)
   ("j a" . text-scale-adjust)             ("j ;" . glyphless-display-mode)
   ("j t" . toggle-truncate-lines)         ("j y" . visual-line-mode)

   ("k e" . json-pretty-print-buffer)      ("k i" . move-to-column)
   ("k s" . space-to-newline)              ("k l" . list-recently-closed)
   ("k d" . ispell-word)                   ("k k" . list-matching-lines)
   ("k f" . delete-matching-lines)
   ("k g" . delete-non-matching-lines)     ("k h" . reformat-to-sentence-lines)
   ("k r" . quote-lines)                   ("k u" . escape-quotes)
   ("k t" . delete-duplicate-lines)        ("k y" . slash-to-double-backslash)
   ("k v" . change-bracket-pairs)          ("k n" . double-backslash-to-slash)
   ("k w" . sort-lines-key-value)          ("k o" . slash-to-backslash)
   ("k x" . insert-column-a-z)             ("k ." . sort-lines-block-or-region)
   ("k c" . cycle-hyphen-lowline-space)    ("k ," . sort-numeric-fields)

   ("l" . describe-foo-at-point)
   (";" . bookmark-bmenu-list)
   ("'" . toggle-debug-on-error)
   ("n" . proced)
   ("m" . downloads)
   ("," . open-last-closed)
   ("." . player)
   ("/" . goto-line)

   ("i ESC" . ignore) ("i <escape>" . ignore)
   ("j ESC" . ignore) ("j <escape>" . ignore)
   ("k ESC" . ignore) ("k <escape>" . ignore)))

(keyamp--dfk
 (define-prefix-command 'keyamp-right-leader-map)
 '(("SPC" . extend-selection)
   ("DEL" . select-line)               ("<backspace>" . select-line)
   ("RET" . eshell)                    ("<return>"    . eshell)
   ("TAB" . news)                      ("<tab>"       . news)
   ("ESC" . ignore)                    ("<escape>"    . ignore)

   ;; right leader left half
   ("`" . ignore)
   ("1" . ignore)
   ("2" . insert-kbd-macro)
   ("3" . ignore)
   ("4" . ignore)
   ("5" . ignore)

   ("q" . fill-or-unfill)
   ("w" . sun-moon)

   ("e e" . todo)                      ("e i" . shopping)
   ("e d" . calendar)                  ("e k" . weather)
   ("e f" . org-time-stamp)            ("e j" . clock)

   ("r" . query-replace-regexp)
   ("t" . calculator)
   ("a" . mark-whole-buffer)
   ("s" . clean-whitespace)

   ("d e" . org-shiftup)               ("d i" . eval-defun)
   ("d s" . shell-command-on-region)   ("d l" . delete-frame)
   ("d d" . insert-date)               ("d k" . run-current-file)
   ("d f" . shell-command)             ("d j" . eval-last-sexp)
   ("d r" . async-shell-command)       ("d u" . elisp-eval-region-or-buffer)
   ("d v" . elisp-byte-compile-file)   ("d n" . stow)

   ("f e" . insert-emacs-quote)        ("f i" . insert-ascii-single-quote)
   ("f f" . insert-char)               ("f j" . insert-brace)
   ("f d" . emoji-insert)              ("f k" . insert-paren)
   ("f s" . insert-formfeed)           ("f l" . insert-square-bracket)
   ("f g" . insert-curly-single-quote) ("f h" . insert-double-curly-quote)
   ("f r" . insert-single-angle-quote) ("f u" . insert-ascii-double-quote)
   ("f t" . insert-double-angle-quote) ("f v" . insert-markdown-quote)

   ("g" . new-empty-buffer)
   ("z" . goto-char)
   ("x" . cut-all)
   ("c" . copy-all)
   ("v" . tasks)
   ("b" . title-case-region-or-line)

   ;; right leader right half
   ("6" . ignore)
   ("7" . increment-register)
   ("8" . insert-register)
   ("9" . ignore)
   ("0" . ignore)
   ("-" . snake)
   ("=" . ignore)

   ("y"  . find-text)
   ("u"  . pop-local-mark-ring)
   ("i"  . copy-file-path)
   ("o"  . set-mark-deactivate-mark)
   ("p"  . show-kill-ring)
   ("["  . toggle-frame-maximized)
   ("]"  . write-file)
   ("\\" . bookmark-delete)

   ("h" . scroll-down-command)
   ("j" . read-only-mode)
   ("k" . make-backup-and-save)
   ("l" . describe-key)
   (";" . scroll-up-command)
   ("'" . sync)

   ("n" . save-buffer)
   ("m" . dired-jump)
   ("," . save-close-current-buffer)
   ("." . recenter-top-bottom)
   ("/" . mark-defun)     ("*" . mark-defun)

   ("e ESC" . ignore) ("e <escape>" . ignore)
   ("d ESC" . ignore) ("d <escape>" . ignore)
   ("f ESC" . ignore) ("f <escape>" . ignore)))

(keyamp--dlk help-map '(lookup-word-definition . lookup-google-translate))
(keyamp--dfk
 help-map
 '(("ESC" . ignore)     ("<escape>" . ignore)
   ("RET" . lookup-web) ("<return>" . lookup-web)

   ("e" . describe-char)          ("i" . info)
   ("s" . info-lookup-symbol)     ("j" . describe-function)
   ("d" . man)                    ("k" . describe-key)
   ("f" . elisp-index-search)     ("l" . describe-variable)

   ("q" . describe-syntax)        ("p" . apropos-documentation)                               ("<f1>" . ignore) ("<help>" . ignore) ("C-w" . ignore) ("C-c" . ignore)
   ("w" . describe-bindings)      ("o" . lookup-all-dictionaries)                             ("C-o"  . ignore) ("C-\\"   . ignore) ("C-n" . ignore) ("C-f" . ignore)
   ("r" . describe-mode)          ("u" . lookup-all-synonyms)                                 ("C-s"  . ignore) ("C-e"    . ignore) ("'"   . ignore) ("6"   . ignore)
   ("a" . describe-face)          (";" . lookup-wiktionary)                                   ("9"    . ignore) ("L"      . ignore) ("n"   . ignore) ("p"   . ignore)
   ("g" . apropos-command)        ("h" . view-lossage)                                        ("?"    . ignore) ("A"      . ignore) ("U"   . ignore) ("S"   . ignore)
   ("z" . apropos-variable)       ("." . lookup-wikipedia)
   ("x" . apropos-value)          ("," . lookup-etymology)
   ("c" . describe-coding-system) ("m" . lookup-word-dict-org)))

(keyamp--dfk query-replace-map '(("C-h" . skip) ("C-r" . act)))
(keyamp--dfk global-map '(("C-r" . open-file-at-cursor) ("C-t" . hippie-expand)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((delete-backward . repeat)))
  (keyamp--dlk x '(repeat . repeat))
  (keyamp--stm x '(repeat)))

(let ((x (make-sparse-keymap)))
  (keyamp--dlk x '(hippie-expand-undo . hippie-expand))
  (keyamp--dfk x '(("<escape>" . ignore)))
  (keyamp--stm x '(hippie-expand)))

(keyamp--dfk
 isearch-mode-map
 '(("<escape>" . isearch-abort)
   ("C-h"   . isearch-repeat-backward) ("C-r"   . isearch-repeat-forward)
   ("C-_ n" . isearch-yank-kill)       ("C-И n" . isearch-yank-kill)))

(let ((x (make-sparse-keymap)))
  (keyamp--dlk x '(isearch-repeat-backward . isearch-repeat-forward))
  (keyamp--dfk
   x
   '(("i" . isearch-ring-retreat)    ("ш" . isearch-ring-retreat)
     ("j" . isearch-repeat-backward) ("о" . isearch-repeat-backward)
     ("k" . isearch-ring-advance)    ("л" . isearch-ring-advance)
     ("l" . isearch-repeat-forward)  ("д" . isearch-repeat-forward)))
  (keyamp--stm
   x
   '(isearch-ring-retreat isearch-repeat-backward isearch-ring-advance
     isearch-repeat-forward search-current-word isearch-yank-kill)))


;; screen

(let ((x (make-sparse-keymap)))
  (keyamp--dkr
   x
   '((backward-kill-word      . sun-moon)                ; w
     (undo                    . split-window-below)      ; e
     (kill-word               . make-frame-command)      ; r
     (backward-word           . switch-to-buffer)        ; u
     (forward-word            . bookmark-jump)           ; o
     (cut-text-block          . calculator)              ; t
     (open-line               . previous-user-buffer)    ; s
     (delete-backward         . delete-other-windows)    ; d
     (newline                 . next-user-buffer)        ; f
     (mark-mode               . new-empty-buffer)        ; g
     (cut-line-or-selection   . works)                   ; x
     (copy-line-or-selection  . agenda)                  ; c
     (paste-or-paste-previous . tasks)                   ; v
     (exchange-point-and-mark . view-echo-area-messages) ; p
     (backward-left-bracket   . dired-jump)              ; m
     (forward-right-bracket   . player)))                ; .
  (keyamp--dfk
   x
   '(("TAB" . toggle-ibuffer)       ("<tab>"       . toggle-ibuffer)
     ("DEL" . previous-user-buffer) ("<backspace>" . previous-user-buffer)
     ("SPC" . next-user-buffer)))
  (keyamp--stm
   x
   '(delete-other-windows         next-user-buffer     previous-user-buffer
     save-close-current-buffer    split-window-below   alternate-buffer
     ibuffer-forward-filter-group ibuffer-backward-filter-group))
  (keyamp--sth x '(ibuffer-hook)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((backward-left-bracket . dired-jump)))
  (keyamp--dlk x '(dired-jump . dired-jump))
  (keyamp--stm x '(dired-jump downloads player)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((next-window-or-frame . save-close-current-buffer)))
  (keyamp--stm x '(save-close-current-buffer)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((delete-backward . tasks) (paste-or-paste-previous . tasks)))
  (keyamp--dlk x '(previous-user-buffer . tasks))
  (keyamp--stm x '(tasks)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((delete-backward . works) (cut-line-or-selection . works)))
  (keyamp--dlk x '(previous-user-buffer . works))
  (keyamp--stm x '(works)))


;; edit

(let ((x (make-sparse-keymap))) ; q d
  (keyamp--dlk x '(delete-backward . insert-space-before))
  (keyamp--stm x '(insert-space-before delete-backward)))

(let ((x (make-sparse-keymap)))
  (keyamp--dlk x '(delete-forward-char . delete-forward-char))
  (keyamp--stm x '(delete-forward-char)))

(let ((x (make-sparse-keymap))) ; w r
  (keyamp--dkr x '((open-line . backward-kill-word) (newline . kill-word)))
  (keyamp--dlk x '(open-line . newline))
  (keyamp--stm x '(backward-kill-word kill-word)))

(let ((x (make-sparse-keymap))) ; e d
  (keyamp--dkr x '((delete-backward . undo-redo)))
  (keyamp--dlk x '(undo . undo-redo))
  (keyamp--stm x '(undo undo-redo)))

(let ((x (make-sparse-keymap))) ; t
  (keyamp--dkr x '((delete-backward . cut-text-block)))
  (keyamp--stm x '(cut-text-block)))

(let ((x (make-sparse-keymap))) ; a
  (keyamp--dkr x '((delete-backward . shrink-whitespaces)))
  (keyamp--dlk x '(shrink-whitespaces . shrink-whitespaces))
  (keyamp--stm x '(shrink-whitespaces)))

(let ((x (make-sparse-keymap))) ; g
  (keyamp--dkr x '((delete-backward . rectangle-mark-mode)))
  (keyamp--stm x '(mark-mode)))

(let ((x (make-sparse-keymap))) ; z
  (keyamp--dkr x '((delete-backward . toggle-comment)))
  (keyamp--dlk x '(toggle-comment . toggle-comment))
  (keyamp--stm x '(toggle-comment)))

(let ((x (make-sparse-keymap))) ; x
  (keyamp--dkr x '((delete-backward . cut-line-or-selection)))
  (keyamp--dlk x '(cut-line-or-selection . cut-line-or-selection))
  (keyamp--stm x '(cut-line-or-selection)))

(let ((x (make-sparse-keymap))) ; c
  (keyamp--dkr x '((delete-backward . copy-line-or-selection)))
  (keyamp--dlk x '(copy-line-or-selection . copy-line-or-selection))
  (keyamp--stm x '(copy-line-or-selection)))

(let ((x (make-sparse-keymap))) ; v
  (keyamp--dkr x '((delete-backward . paste-or-paste-previous)))
  (keyamp--dlk x '(undo . paste-or-paste-previous))
  (keyamp--stm x '(paste-or-paste-previous)))

(let ((x (make-sparse-keymap))) ; b
  (keyamp--dkr x '((delete-backward . toggle-letter-case)))
  (keyamp--dlk x '(toggle-letter-case . toggle-letter-case))
  (keyamp--stm x '(toggle-letter-case)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr
   x
   '((undo . org-shiftup) (delete-backward . org-shiftdown)
     (copy-line-or-selection . agenda)))
  (keyamp--dlk x '(org-shiftup . org-shiftdown))
  (keyamp--stm x '(org-shiftup org-shiftdown)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((undo . todo) (copy-line-or-selection . agenda)))
  (keyamp--stm x '(todo insert-date)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((delete-backward . cycle-hyphen-lowline-space)))
  (keyamp--stm x '(cycle-hyphen-lowline-space)))


;; move

(let ((x (make-sparse-keymap)))
  (keyamp--dlk x '(previous-line . next-line))
  (keyamp--stm x '(previous-line next-line)))

(let ((x (make-sparse-keymap)))
  (keyamp--dlk x '(up-line . down-line))
  (keyamp--stm x '(up-line down-line)))

(let ((x (make-sparse-keymap)))
  (keyamp--dlk x '(backward-left-bracket . forward-right-bracket))
  (keyamp--stm x '(backward-left-bracket forward-right-bracket)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr
   x
   '((previous-line              . beginning-of-line-or-block)
     (next-line                  . end-of-line-or-block)
     (beginning-of-line-or-block . beginning-of-line-or-buffer)
     (end-of-line-or-block       . end-of-line-or-buffer)))
  (keyamp--dlk x '(previous-line . next-line))
  (keyamp--stm
   x
   '(beginning-of-line-or-block end-of-line-or-block
     beginning-of-line-or-buffer end-of-line-or-buffer)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr
   x
   '((backward-char . backward-word)  (forward-char . forward-word)
     (backward-word . backward-punct) (forward-word . forward-punct)))
  (keyamp--dlk x '(backward-char . forward-char))
  (keyamp--stm
   x
   '(backward-word forward-word backward-punct forward-punct
     mark-mode exchange-point-and-mark rectangle-mark-mode)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((previous-line . scroll-down-line) (next-line . scroll-up-line)))
  (keyamp--dlk x '(scroll-down-line . scroll-up-line))
  (keyamp--stm x '(scroll-down-line scroll-up-line)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((previous-line . scroll-down-command) (next-line . scroll-up-command)))
  (keyamp--dlk x '(scroll-down-command . scroll-up-command))
  (keyamp--stm x '(scroll-down-command scroll-up-command)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((next-line . pop-local-mark-ring)))
  (keyamp--dlk x '(pop-local-mark-ring . pop-local-mark-ring))
  (keyamp--stm x '(pop-local-mark-ring)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((next-line . recenter-top-bottom)))
  (keyamp--dlk x '(recenter-top-bottom . recenter-top-bottom))
  (keyamp--stm x '(recenter-top-bottom)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((previous-line . beginning-of-line-or-block) (next-line . select-block)))
  (keyamp--dlk x '(previous-line . next-line))
  (keyamp--stm x '(select-block)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr
   x
   '((next-line     . extend-selection)
     (backward-char . backward-word)  (forward-char  . forward-word)
     (backward-word . backward-punct) (forward-word  . forward-punct)))
  (keyamp--dlk x '(backward-char . forward-char))
  (keyamp--stm x '(extend-selection)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((next-line . select-line)))
  (keyamp--dlk x '(previous-line . next-line))
  (keyamp--stm x '(select-line)))

(let ((x (make-sparse-keymap)))
  (keyamp--dkr x '((next-line . select-text-in-quote)))
  (keyamp--stm x '(select-text-in-quote)))


;; modes

(setq keyamp-minibuffer-map (make-sparse-keymap))
(keyamp--dlk
 keyamp-minibuffer-map '(previous-line-or-history-element . next-line-or-history-element))

(with-eval-after-load 'minibuffer
  (keyamp--dkr
   minibuffer-local-map
   '((previous-line . previous-line-or-history-element)
     (next-line     . next-line-or-history-element)
     (select-block  . previous-line-or-history-element)))
  (keyamp--dkr
   minibuffer-mode-map
   '((previous-line       . previous-line-or-history-element)
     (next-line           . next-line-or-history-element)
     (open-file-at-cursor . exit-minibuffer)
     (select-block        . previous-line-or-history-element))))

(with-eval-after-load 'icomplete
  (keyamp--dfk
   icomplete-minibuffer-map
   '(("C-r" . icomplete-force-complete-and-exit)
     ("RET" . icomplete-exit-or-force-complete-and-exit)
     ("<return>" . icomplete-exit-or-force-complete-and-exit)))

  (keyamp--dkr
   icomplete-minibuffer-map
   '((previous-line    . icomplete-backward-completions)
     (next-line        . icomplete-forward-completions)
     (select-block     . previous-line-or-history-element)
     (extend-selection . next-line-or-history-element)))

  (let ((x (make-sparse-keymap)))
    (keyamp--dkr
     x
     '((previous-line . previous-line-or-history-element)
       (next-line     . next-line-or-history-element)
       (keyamp-insert . exit-minibuffer)))
    (keyamp--dlk x '(previous-line . next-line))
    (keyamp--stm x '(previous-line-or-history-element next-line-or-history-element))))

  (let ((x (make-sparse-keymap)))
    (keyamp--dkr
     x
     '((previous-line . previous-line-or-history-element)
       (next-line     . next-line-or-history-element)))
    (keyamp--sth x '(icomplete-minibuffer-setup-hook)))

  (let ((x (make-sparse-keymap)))
    (keyamp--dkr
     x
     '((previous-line . icomplete-backward-completions)
       (next-line     . icomplete-forward-completions)))
    (keyamp--dlk x '(previous-line . next-line))
    (keyamp--stm x '(icomplete-backward-completions icomplete-forward-completions)))

(add-hook 'ido-setup-hook
          (lambda ()
            (keyamp--dfk ido-completion-map '(("C-r" . ido-exit-minibuffer)))
            (keyamp--dkr
             ido-completion-map
             '((previous-line . ido-prev-match)
               (next-line     . ido-next-match)))
            (let ((x (make-sparse-keymap)))
              (keyamp--dlk x '(previous-line . next-line))
              (keyamp--stm x '(ido-prev-match ido-next-match)))))

(progn ; dired
  (with-eval-after-load 'dired
    (keyamp--dfk dired-mode-map '(("C-h" . dired-do-delete) ("C-r" . open-in-external-app)))
    (keyamp--dkr
     dired-mode-map
     '((keyamp-insert         . dired-find-file)
       (backward-left-bracket . dired-mark)
       (forward-right-bracket . dired-unmark)
       (toggle-comment        . revert-buffer)
       (copy-to-register-1    . dired-do-copy)
       (paste-from-register-1 . dired-do-rename)
       (mark-whole-buffer     . dired-toggle-marks)
       (reformat-lines        . dired-create-directory)
       (insert-space-before   . dired-hide-details-mode)))

    (let ((x (make-sparse-keymap)))
      (keyamp--dlk x '(dired-previous-line . dired-next-line))
      (keyamp--stm x '(dired-previous-line dired-next-line)))

    (let ((x (make-sparse-keymap)))
      (keyamp--dlk x '(dired-unmark . dired-mark))
      (keyamp--stm x '(dired-unmark dired-mark))))

  (with-eval-after-load 'wdired
    (keyamp--dfk wdired-mode-map '(("C-h" . wdired-abort-changes) ("C-r" . wdired-finish-edit)))))

(with-eval-after-load 'rect
  (keyamp--dkr
   rectangle-mark-mode-map
   '((copy-line-or-selection  . copy-rectangle-as-kill)
     (delete-backward         . kill-rectangle)
     (keyamp-insert           . string-rectangle)
     (paste-or-paste-previous . yank-rectangle)
     (copy-to-register        . copy-rectangle-to-register)
     (toggle-comment          . rectangle-number-lines)
     (cut-line-or-selection   . clear-rectangle)
     (insert-space-before     . open-rectangle)
     (clean-whitespace        . delete-whitespace-rectangle))))

(progn ; ibuffer
  (with-eval-after-load 'ibuf-ext
    (keyamp--dfk
     ibuffer-mode-map
     '(("C-h" . ibuffer-do-delete) ("TAB" . news) ("<tab>" . news)))

    (keyamp--dkr
     ibuffer-mode-map
     '((keyamp-insert              . ibuffer-visit-buffer)
       (end-of-line-or-block       . ibuffer-forward-filter-group)
       (beginning-of-line-or-block . ibuffer-backward-filter-group)
       (previous-line              . up-line)
       (next-line                  . down-line)))
    (keyamp--dfk ibuffer-mode-filter-group-map '(("C-h" . help-command)))
    (keyamp--dkr ibuffer-mode-filter-group-map '((keyamp-insert . ibuffer-toggle-filter-group)))

    (let ((x (make-sparse-keymap)))
      (keyamp--dkr
       x
       '((previous-line              . ibuffer-backward-filter-group)
         (next-line                  . ibuffer-forward-filter-group)
         (beginning-of-line-or-block . beginning-of-line-or-buffer)
         (end-of-line-or-block       . end-of-line-or-buffer)))
      (keyamp--stm x '(ibuffer-backward-filter-group ibuffer-forward-filter-group ibuffer-toggle-filter-group))))

  (let ((x (make-sparse-keymap)))
    (keyamp--dkr x '((delete-backward . ibuffer-do-delete)))
    (keyamp--dlk x '(ibuffer-do-delete . ibuffer-do-delete))
    (keyamp--stm x '(ibuffer-do-delete))))

(with-eval-after-load 'transient
  (keyamp--dfk transient-base-map '(("<escape>" . transient-quit-one))))

(progn ; remap RET
  (with-eval-after-load 'arc-mode (keyamp--dkr archive-mode-map '((keyamp-insert . archive-extract))))
  (with-eval-after-load 'bookmark (keyamp--dkr bookmark-bmenu-mode-map '((keyamp-insert . bookmark-bmenu-this-window))))
  (with-eval-after-load 'button (keyamp--dkr button-map '((keyamp-insert . push-button))))
  (with-eval-after-load 'compile (keyamp--dkr compilation-button-map '((keyamp-insert . compile-goto-error))))
  (with-eval-after-load 'gnus-art (keyamp--dkr gnus-mime-button-map '((keyamp-insert . gnus-article-press-button))))
  (with-eval-after-load 'emms-playlist-mode (keyamp--dkr emms-playlist-mode-map '((keyamp-insert . emms-playlist-mode-play-smart))))
  (with-eval-after-load 'org-agenda (keyamp--dkr org-agenda-mode-map '((keyamp-insert . org-agenda-switch-to))))
  (with-eval-after-load 'replace (keyamp--dkr occur-mode-map '((keyamp-insert . occur-mode-goto-occurrence))))
  (with-eval-after-load 'shr (keyamp--dkr shr-map '((keyamp-insert . shr-browse-url))))
  (with-eval-after-load 'simple (keyamp--dkr completion-list-mode-map '((keyamp-insert . choose-completion))))
  (with-eval-after-load 'wid-edit (keyamp--dkr widget-link-keymap '((keyamp-insert . widget-button-press)))))

(with-eval-after-load 'doc-view
  (keyamp--dkr
   doc-view-mode-map
   '((previous-line              . doc-view-previous-line-or-previous-page)
     (next-line                  . doc-view-next-line-or-next-page)
     (backward-char              . doc-view-previous-page)
     (forward-char               . doc-view-next-page)
     (backward-word              . doc-view-shrink)
     (forward-word               . doc-view-enlarge)
     (beginning-of-line-or-block . doc-view-scroll-down-or-previous-page)
     (end-of-line-or-block       . doc-view-scroll-up-or-next-page)))

  (let ((x (make-sparse-keymap)))
    (keyamp--dkr
     x
     '((previous-line . doc-view-scroll-down-or-previous-page)
       (next-line     . doc-view-scroll-up-or-next-page)))
    (keyamp--dlk x '(doc-view-scroll-down-or-previous-page . doc-view-scroll-up-or-next-page))
    (keyamp--stm x '(doc-view-scroll-down-or-previous-page doc-view-scroll-up-or-next-page))))

(with-eval-after-load 'image-mode
  (keyamp--dkr image-mode-map '((backward-char . image-previous-file) (forward-char . image-next-file)))
  (let ((x (make-sparse-keymap)))
    (keyamp--dlk x '(backward-char . forward-char))
    (keyamp--stm x '(image-previous-file image-next-file))))

(with-eval-after-load 'esh-mode
  (keyamp--dfk eshell-mode-map '(("C-h" . eshell-interrupt-process) ("C-r" . eshell-send-input)))
  (keyamp--dkr
   eshell-mode-map
   '((cut-line-or-selection . eshell-clear-input)
     (cut-all               . eshell-clear)
     (select-block          . eshell-previous-input)))
  (let ((x (make-sparse-keymap)))
    (keyamp--dkr
     x
     '((previous-line . eshell-previous-input)
       (next-line     . eshell-next-input)))
    (keyamp--dlk x '(previous-line . next-line))
    (keyamp--stm x '(eshell-previous-input eshell-next-input))
    (add-hook 'eshell-post-command-hook (lambda () "History search."
                                          (set-transient-map x)
                                          (setq this-command 'next-line)
                                          (set-face-background 'cursor keyamp-repeat-cursor)))))

(with-eval-after-load 'term
  (keyamp--dfk
   term-raw-map
   '(("C-h" . term-interrupt-subjob) ("C-r" . term-send-input) ("C-c C-c" . term-line-mode)))
  (keyamp--dfk
   term-mode-map
   '(("C-h" . term-interrupt-subjob) ("C-r" . term-send-input) ("C-c C-c" . term-char-mode)))
  (keyamp--dkr term-mode-map '((select-block . term-send-up)))
  (let ((x (make-sparse-keymap)))
    (keyamp--dkr x '((previous-line . term-send-up) (next-line . term-send-down)))
    (keyamp--dlk x '(previous-line . next-line))
    (keyamp--stm x '(term-send-up term-send-down))
    (keyamp--sth x '(term-mode-hook))
    (add-hook 'term-input-filter-functions (lambda (&rest r) "History search."
                                             (set-transient-map x)
                                             (keyamp-command)
                                             (setq this-command 'next-line)))))

(with-eval-after-load 'info
  (keyamp--dkr
   Info-mode-map
   '((open-line       . Info-backward-node)
     (newline         . Info-forward-node)
     (delete-backward . Info-next-reference)
     (undo            . Info-up)
     (keyamp-insert   . Info-follow-nearest-node)
     (down-line       . scroll-down-line)
     (up-line         . scroll-up-line)
     (right-char      . Info-backward-node)
     (left-char       . Info-forward-node)))
  (keyamp--dfk Info-mode-map '(("TAB" . scroll-up-command) ("<tab>" . scroll-up-command)))
  (let ((x (make-sparse-keymap)))
    (keyamp--dlk x '(open-line . newline))
    (keyamp--stm x '(Info-backward-node Info-forward-node))))

(with-eval-after-load 'help-mode
  (keyamp--dkr
   help-mode-map
   '((delete-backward . forward-button)
     (undo            . backward-button)
     (open-line       . help-go-back)
     (newline         . help-go-forward))))

(progn ; gnus
  (with-eval-after-load 'gnus-topic
    (keyamp--dfk gnus-topic-mode-map '(("TAB" . toggle-ibuffer) ("<tab>" . toggle-ibuffer)))
    (keyamp--dkr
     gnus-topic-mode-map
     '((keyamp-insert . gnus-topic-select-group)
       (beginning-of-line-or-block  . gnus-topic-goto-previous-topic-line)
       (end-of-line-or-block        . gnus-topic-goto-next-topic-line)
       (previous-line               . up-line)
       (next-line                   . down-line)))
    (let ((x (make-sparse-keymap)))
      (keyamp--dkr
       x
       '((previous-line              . gnus-topic-goto-previous-topic-line)
         (next-line                  . gnus-topic-goto-next-topic-line)
         (beginning-of-line-or-block . gnus-beginning-of-line-or-buffer)
         (end-of-line-or-block       . gnus-end-of-line-or-buffer)))
      (keyamp--dlk x '(previous-line . next-line))
      (keyamp--stm
       x
       '(gnus-topic-goto-previous-topic-line
         gnus-topic-goto-next-topic-line
         gnus-beginning-of-line-or-buffer
         gnus-end-of-line-or-buffer))))

  (with-eval-after-load 'gnus-group
    (keyamp--dkr
     gnus-group-mode-map
     '((undo            . gnus-group-enter-server-mode)
       (delete-backward . gnus-group-get-new-news))))

  (with-eval-after-load 'gnus-sum
    (keyamp--dfk
     gnus-summary-mode-map
     '(("C-h" . gnus-summary-delete-article)
       ("TAB" . scroll-up-command) ("<tab>" . scroll-up-command)))
    (keyamp--dkr
     gnus-summary-mode-map
     '((keyamp-insert       . gnus-summary-scroll-up)
       (open-file-at-cursor . keyamp-insert)
       (undo                . gnus-summary-prev-article)
       (delete-backward     . gnus-summary-next-article)
       (open-line           . gnus-summary-prev-group)
       (newline             . gnus-summary-next-group)
       (kill-word           . gnus-summary-save-parts)
       (down-line           . scroll-down-line)
       (up-line             . scroll-up-line)
       (right-char          . gnus-summary-prev-group)
       (left-char           . gnus-summary-next-group)))

    (let ((x (make-sparse-keymap)))
      (keyamp--dkr
       x
       '((undo            . gnus-summary-prev-article)
         (delete-backward . gnus-summary-next-article)
         (open-line       . gnus-summary-prev-group)
         (newline         . gnus-summary-next-group)
         (down-line       . scroll-down-line)
         (up-line         . scroll-up-line)
         (right-char      . gnus-summary-prev-group)
         (left-char       . gnus-summary-next-group)))
      (keyamp--dlk x '(gnus-summary-prev-group . gnus-summary-next-group))
      (keyamp--stm x '(gnus-summary-prev-group gnus-summary-next-group))
      (keyamp--sth x '(gnus-summary-prepared-hook)))

    (let ((x (make-sparse-keymap)))
      (keyamp--dlk x '(gnus-summary-prev-article . gnus-summary-next-article))
      (keyamp--stm x '(gnus-summary-prev-article gnus-summary-next-article))))

  (with-eval-after-load 'gnus-srvr
    (keyamp--dkr
     gnus-server-mode-map
     '((keyamp-insert       . gnus-server-read-server)
       (open-file-at-cursor . keyamp-insert)
       (delete-backward     . gnus-server-exit)))
    (keyamp--dkr
     gnus-browse-mode-map
     '((keyamp-insert       . gnus-browse-select-group)
       (open-file-at-cursor . keyamp-insert)))))

(with-eval-after-load 'snake
  (keyamp--dkr
   snake-mode-map
   '((keyamp-insert        . snake-start-game) (keyamp-escape   . snake-pause-game)
     (next-line            . snake-move-down)  (delete-backward . snake-move-up)
     (delete-other-windows . snake-rotate-up)))

  (let ((x (make-sparse-keymap)))
    (keyamp--dlk x '(snake-move-left . snake-move-right))
    (keyamp--stm
     x
     '(snake-start-game snake-pause-game snake-move-left
       snake-move-right snake-move-down snake-move-up))
    (keyamp--sth x '(snake-mode-hook))))

(with-eval-after-load 'tetris
  (keyamp--dkr
   tetris-mode-map
   '((keyamp-escape   . tetris-pause-game)
     (delete-backward . tetris-rotate-prev) (delete-other-windows . tetris-rotate-prev)
     (newline         . tetris-rotate-next) (next-user-buffer     . tetris-rotate-next)
     (next-line       . tetris-move-bottom) (backward-char        . tetris-move-down)))

  (let ((x (make-sparse-keymap)))
    (keyamp--dlk x '(tetris-move-left . tetris-move-right))
    (keyamp--stm
     x
     '(tetris-start-game tetris-pause-game tetris-move-left tetris-move-right
       tetris-rotate-prev tetris-rotate-next tetris-move-bottom tetris-move-down))))

(with-eval-after-load 'nov
  (keyamp--dkr
   nov-mode-map
   '((undo    . nov-goto-toc)      (open-line     . nov-previous-document)
     (newline . nov-next-document) (keyamp-insert . nov-browse-url))))



(setq keyamp-repeat-commands-hash
      #s(hash-table
         size 100
         test equal
         data (Info-backward-node                  t
               Info-forward-node                   t
               agenda                              t
               alternate-buffer                    t
               backward-punct                      t
               backward-word                       t
               beginning-of-line-or-block          t
               beginning-of-line-or-buffer         t
               backward-left-bracket               t
               comint-next-input                   t
               comint-previous-input               t
               copy-line-or-selection              t
               delete-backward                     t
               cycle-hyphen-lowline-space          t
               delete-forward-char                 t
               delete-other-windows                t
               describe-function                   t
               describe-key                        t
               describe-variable                   t
               dired-jump                          t
               dired-mark                          t
               dired-next-line                     t
               dired-previous-line                 t
               dired-unmark                        t
               down-line                           t
               downloads                           t
               end-of-line-or-block                t
               end-of-line-or-buffer               t
               eshell-next-input                   t
               eshell-previous-input               t
               exchange-point-and-mark             t
               extend-selection                    t
               forward-punct                       t
               forward-right-bracket               t
               forward-word                        t
               gnus-beginning-of-line-or-buffer    t
               gnus-end-of-line-or-buffer          t
               gnus-summary-next-article           t
               gnus-summary-next-group             t
               gnus-summary-prev-article           t
               gnus-summary-prev-group             t
               gnus-topic-goto-next-topic-line     t
               gnus-topic-goto-previous-topic-line t
               hippie-expand                       t
               hippie-expand-undo                  t
               ibuffer-backward-filter-group       t
               ibuffer-forward-filter-group        t
               icomplete-backward-completions      t
               icomplete-forward-completions       t
               ido-next-match                      t
               ido-prev-match                      t
               insert-date                         t
               insert-space-before                 t
               isearch-repeat-backward             t
               isearch-repeat-forward              t
               isearch-ring-advance                t
               isearch-ring-retreat                t
               isearch-yank-kill                   t
               kill-region                         t
               mark-mode                           t
               move-row-down                       t
               move-row-up                         t
               next-line                           t
               next-line-or-history-element        t
               next-user-buffer                    t
               org-shiftdown                       t
               org-shiftup                         t
               pop-local-mark-ring                 t
               previous-line                       t
               previous-line-or-history-element    t
               previous-user-buffer                t
               recenter-top-bottom                 t
               rectangle-mark-mode                 t
               save-close-current-buffer           t
               scroll-down-command                 t
               scroll-up-command                   t
               search-current-word                 t
               select-line                         t
               select-text-in-quote                t
               shrink-whitespaces                  t
               split-window-below                  t
               sun-moon                            t
               tasks                               t
               term-send-down                      t
               term-send-up                        t
               todo                                t
               toggle-comment                      t
               toggle-letter-case                  t
               undo                                t
               undo-redo                           t
               up-line                             t
               view-echo-area-messages             t
               works                               t
               yank                                t
               yank-pop                            t)))



(defvar keyamp-insert-state-p t "Non-nil means insertion mode is on.")
(defvar keyamp-insert-idle-timer nil "Idle timer for exit insert mode.")
(defvar keyamp-repeat-idle-timer nil "Idle timer for exit repeat mode.")

(defun keyamp-command-init ()
  "Set command mode keys."
  (setq keyamp-insert-state-p nil)
  (when keyamp--deactivate-command-mode-func
    (funcall keyamp--deactivate-command-mode-func))
  (setq keyamp--deactivate-command-mode-func
        (set-transient-map keyamp-command-map (lambda () t)))
  (set-face-background 'cursor keyamp-command-cursor)
  (setq mode-line-front-space keyamp-command-indicator)
  (force-mode-line-update)
  (when (active-minibuffer-window)
    (set-transient-map keyamp-minibuffer-map)
    (setq this-command 'next-line))
  (when (timerp keyamp-insert-idle-timer)
    (cancel-timer keyamp-insert-idle-timer)))

(defun keyamp-insert-init ()
  "Enter insert mode."
  (setq keyamp-insert-state-p t)
  (funcall keyamp--deactivate-command-mode-func)
  (set-face-background 'cursor keyamp-insert-cursor)
  (setq mode-line-front-space keyamp-insert-indicator)
  (force-mode-line-update)
  (setq keyamp-insert-idle-timer
        (run-with-idle-timer keyamp-idle-timeout nil 'keyamp-escape)))

(defun keyamp-command-init-karabiner ()
  "Karabiner integration. Init command mode with `keyamp-command-hook'."
  (call-process keyamp-karabiner-cli nil 0 nil
                "--set-variables" "{\"insert mode activated\":0}"))

(defun keyamp-insert-init-karabiner ()
  "Karabiner integration. Init insert mode with `keyamp-insert-hook'."
  (call-process keyamp-karabiner-cli nil 0 nil
                "--set-variables" "{\"insert mode activated\":1}"))

(defun keyamp-command ()
  "Activate command mode."
  (interactive)
  (keyamp-command-init)
  (run-hooks 'keyamp-command-hook))

(defun keyamp-insert ()
  "Activate insert mode."
  (interactive)
  (keyamp-insert-init)
  (run-hooks 'keyamp-insert-hook))

(defun keyamp-repeat ()
  "Indicate repeat mode. Run with `post-command-hook'."
  (if (or (gethash this-command keyamp-repeat-commands-hash)
          (eq real-this-command 'repeat))
      (progn
        (setq mode-line-front-space keyamp-repeat-indicator)
        (set-face-background 'cursor keyamp-repeat-cursor))
    (if keyamp-insert-state-p
        (progn
          (setq mode-line-front-space keyamp-insert-indicator)
          (set-face-background 'cursor keyamp-insert-cursor))
      (setq mode-line-front-space keyamp-command-indicator)
      (set-face-background 'cursor keyamp-command-cursor))
    (force-mode-line-update)))

(defun keyamp-escape (&optional Idle)
  "Return to command mode. Escape everything.
If run by idle timer then emulate keyboard press to cancel repeat."
  (interactive)
  (cond
   (Idle                       (execute-kbd-macro (kbd "<escape>")))
   (keyamp-insert-state-p      (keyamp-command))
   ((region-active-p)          (deactivate-mark))
   ((active-minibuffer-window) (abort-recursive-edit))))



;;;###autoload
(define-minor-mode keyamp
  "Key Amplifier."
  :global t
  :keymap keyamp-map

  (when keyamp
    (add-hook 'minibuffer-setup-hook   'keyamp-command)
    (add-hook 'minibuffer-exit-hook    'keyamp-command)
    (add-hook 'isearch-mode-end-hook   'keyamp-command)
    (add-hook 'eshell-pre-command-hook 'keyamp-command)
    (add-hook 'post-command-hook       'keyamp-repeat)
    (when (file-exists-p keyamp-karabiner-cli)
      (add-hook 'keyamp-insert-hook  'keyamp-insert-init-karabiner)
      (add-hook 'keyamp-command-hook 'keyamp-command-init-karabiner))
    (keyamp-catch-tty-ESC)
    (keyamp-define-input-source 'russian-computer)
    (keyamp-command)
    (setq keyamp-repeat-idle-timer
          (run-with-idle-timer keyamp-idle-timeout t 'keyamp-escape t))))

(provide 'keyamp)

;; Local Variables:
;; byte-compile-warnings: (not free-vars lexical)
;; End:
;;; keyamp.el ends here