;;; http-lib.el --- HTTP library                         -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Adam Porter

;; Author: Adam Porter <adam@alphapapa.net>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; An HTTP library that uses curl as a backend.  Inspired by, and some
;; code copied from, Christopher Wellons's library, elfeed-curl.el.

;;; Code:

;;;; Requirements

(require 'cl-lib)
(require 'subr-x)

;;;; Structs

(cl-defstruct http-lib-response
  version status headers body)

;;;; Constants

(defconst http-lib-curl-errors
  ;; Copied from elfeed-curl.el.
  '((1 . "Unsupported protocol.")
    (2 . "Failed to initialize.")
    (3 . "URL malformed. The syntax was not correct.")
    (4 . "A feature or option that was needed to perform the desired request was not enabled or was explicitly disabled at build-time.")
    (5 . "Couldn't resolve proxy. The given proxy host could not be resolved.")
    (6 . "Couldn't resolve host. The given remote host was not resolved.")
    (7 . "Failed to connect to host.")
    (8 . "FTP weird server reply. The server sent data curl couldn't parse.")
    (9 . "FTP access denied.")
    (11 . "FTP weird PASS reply.")
    (13 . "FTP weird PASV reply.")
    (14 . "FTP weird 227 format.")
    (15 . "FTP can't get host.")
    (17 . "FTP couldn't set binary.")
    (18 . "Partial file. Only a part of the file was transferred.")
    (19 . "FTP couldn't download/access the given file, the RETR (or similar) command failed.")
    (21 . "FTP quote error. A quote command returned error from the server.")
    (22 . "HTTP page not retrieved.")
    (23 . "Write error.")
    (25 . "FTP couldn't STOR file.")
    (26 . "Read error. Various reading problems.")
    (27 . "Out of memory. A memory allocation request failed.")
    (28 . "Operation timeout.")
    (30 . "FTP PORT failed.")
    (31 . "FTP couldn't use REST.")
    (33 . "HTTP range error. The range \"command\" didn't work.")
    (34 . "HTTP post error. Internal post-request generation error.")
    (35 . "SSL connect error. The SSL handshaking failed.")
    (36 . "FTP bad download resume.")
    (37 . "FILE couldn't read file.")
    (38 . "LDAP bind operation failed.")
    (39 . "LDAP search failed.")
    (41 . "Function not found. A required LDAP function was not found.")
    (42 . "Aborted by callback.")
    (43 . "Internal error. A function was called with a bad parameter.")
    (45 . "Interface error. A specified outgoing interface could not be used.")
    (47 . "Too many redirects.")
    (48 . "Unknown option specified to libcurl.")
    (49 . "Malformed telnet option.")
    (51 . "The peer's SSL certificate or SSH MD5 fingerprint was not OK.")
    (52 . "The server didn't reply anything, which here is considered an error.")
    (53 . "SSL crypto engine not found.")
    (54 . "Cannot set SSL crypto engine as default.")
    (55 . "Failed sending network data.")
    (56 . "Failure in receiving network data.")
    (58 . "Problem with the local certificate.")
    (59 . "Couldn't use specified SSL cipher.")
    (60 . "Peer certificate cannot be authenticated with known CA certificates.")
    (61 . "Unrecognized transfer encoding.")
    (62 . "Invalid LDAP URL.")
    (63 . "Maximum file size exceeded.")
    (64 . "Requested FTP SSL level failed.")
    (65 . "Sending the data requires a rewind that failed.")
    (66 . "Failed to initialise SSL Engine.")
    (67 . "The user name, password, or similar was not accepted and curl failed to log in.")
    (68 . "File not found on TFTP server.")
    (69 . "Permission problem on TFTP server.")
    (70 . "Out of disk space on TFTP server.")
    (71 . "Illegal TFTP operation.")
    (72 . "Unknown TFTP transfer ID.")
    (73 . "File already exists (TFTP).")
    (74 . "No such user (TFTP).")
    (75 . "Character conversion failed.")
    (76 . "Character conversion functions required.")
    (77 . "Problem with reading the SSL CA cert (path? access rights?).")
    (78 . "The resource referenced in the URL does not exist.")
    (79 . "An unspecified error occurred during the SSH session.")
    (80 . "Failed to shut down the SSL connection.")
    (82 . "Could not load CRL file, missing or wrong format (added in 7.19.0).")
    (83 . "Issuer check failed (added in 7.19.0).")
    (84 . "The FTP PRET command failed")
    (85 . "RTSP: mismatch of CSeq numbers")
    (86 . "RTSP: mismatch of Session Identifiers")
    (87 . "unable to parse FTP file list")
    (88 . "FTP chunk callback reported error")
    (89 . "No connection available, the session will be queued")
    (90 . "SSL public key does not matched pinned public key"))
  "Alist mapping curl error code integers to helpful error messages.")

;;;; Variables

(defvar-local http-lib-error nil
  "Callback function for errored completion of request in current curl process buffer.")

(defvar-local http-lib-success nil
  "Callback function for successful completion of request in current curl process buffer.")

;;;; Customization

(defgroup http-lib nil
  "Options for `http-lib'."
  :group 'network)

(defcustom http-lib-curl-program "curl"
  "Name of curl program to call."
  :type 'string)

(defcustom http-lib-curl-default-args
  '("--silent"
    "--compressed"
    "--location"
    ;;  "--write-out" "(http-lib-curl-request . %%{size_header})"
    "--connect-timeout" "5"
    "--dump-header" "-")
  "Default arguments to curl."
  :type '(repeat string))

;; (defcustom http-lib-curl-connection-timeout 5
;;   "Default connection timeout for HTTP requests made with curl.
;; The --connect-timeout option for curl.")

;;;; Commands


;;;; Functions

(cl-defun http-lib-get (url &key headers _connect-timeout
                            success error)
  "FIXME: Docstring."
  (http-lib-request 'get url
                    :headers headers
                    ;;  :connect-timeout timeout
                    :success success
                    :error error))

(cl-defun http-lib-request (_method url &key headers _connect-timeout
                                    success error)
  "FIXME: Docstring."
  ;; Inspired by and copied from `elfeed-curl-retrieve'.
  (with-current-buffer (generate-new-buffer "*http-lib-request-curl*")
    (let* ((coding-system-for-read 'binary)
           (process-connection-type nil)
           (header-args (cl-loop for (key . value) in headers
                                 collect (format "--header %s: %s" key value)))
           (curl-args (append http-lib-curl-default-args header-args
                              (list url)))
           (process (apply #'start-process "http-lib-request-curl" (current-buffer)
                           http-lib-curl-program curl-args)))
      (setf http-lib-success success
            http-lib-error error
            (process-sentinel process) #'http-lib--sentinel)
      process)))

(defun http-lib--sentinel (process status)
  "FIXME: Docstring."
  ;; Inspired by and some code copied from `elfeed-curl--sentinel'.
  (let ((buffer (process-buffer process)))
    (unwind-protect
        (with-current-buffer buffer
          (pcase status
            ("finished\n"
             ;; Request completed successfully: call success callback with parsed response.
             (let ((response (http-lib--parse-response buffer)))
               (funcall http-lib-success response)))

            ((rx "exited abnormally with code " (group (1+ digit)))
             ;; Error: call error callback.
             ;; FIXME: Call with an error struct.
             (warn "http-lib--sentinel: ERROR: %s" (buffer-string))
             ;; (let* ((code (string-to-number (match-string 1 status)))
             ;;        (message (alist-get code http-lib-curl-errors)))
             ;;   (funcall http-lib-error (http-lib--parse-response buffer)))
             )))
      (kill-buffer buffer))))

(defun http-lib--parse-response (buffer)
  "FIXME: Docstring."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      ;; Parse HTTP version and status code.
      (looking-at (rx "HTTP/" (group (1+ (or digit "."))) (1+ blank)
                      (group (1+ digit))))
      (let* ((http-version (string-to-number (match-string 1)))
             (status-code (string-to-number (match-string 2)))
             (headers (http-lib--headers buffer))
             (coding-system (or (when-let* ((it (alist-get "Content-Type" headers nil nil #'string=)))
                                  (coding-system-from-name it))
                                'utf-8))
             (body (http-lib--decode-body buffer coding-system)))
        (make-http-lib-response
         :version http-version
         :status status-code
         :headers headers
         :body body)))))

(defun http-lib--headers (buffer)
  "FIXME: Docstring."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (forward-line 1)
      (let ((limit (save-excursion
                     (re-search-forward "^\r\n" nil)
                     (point))))
        (cl-loop while (re-search-forward (rx bol (group (1+ (not (in ":")))) ":" (1+ blank)
                                              (group (1+ (not (in "\r\n")))))
                                          limit t)
                 collect (cons (match-string 1) (match-string 2)))))))

(defun http-lib--decode-body (buffer coding-system)
  "FIXME: Docstring."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      ;; Skip headers.
      (re-search-forward "^\r\n" nil)
      (decode-coding-region (point) (point-max) coding-system t))))


;;;; Footer

(provide 'http-lib)

;;; http-lib.el ends here