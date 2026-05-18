EMACS ?= emacs

FILES = helixel-action.el helixel-edit.el helixel-repeat.el helixel-register.el helixel-state.el helixel-move.el helixel-keymap.el helixel-common.el helixel-search.el helixel-delimiter.el helixel-textobj-engine.el helixel-surround.el helixel-textobj.el helixel.el
ELS := helixel-action.elc helixel-edit.elc helixel-repeat.elc helixel-register.elc helixel-state.elc helixel-move.elc helixel-keymap.elc helixel-common.elc helixel-search.elc helixel-delimiter.elc helixel-textobj-engine.elc helixel-surround.elc helixel-textobj.elc helixel.elc

TEST_FILES = $(wildcard test/helixel-test-*.el)

DEPS = package-lint

INIT_PACKAGES="(progn \
  (require 'package) \
  (push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives) \
  (package-initialize) \
  (push (expand-file-name \".\") load-path) \
  (dolist (pkg '(${DEPS})) \
    (unless (package-installed-p pkg) \
      (unless (assoc pkg package-archive-contents) \
	(package-refresh-contents)) \
      (package-install pkg))) \
  (unless package-archive-contents (package-refresh-contents)) \
  )"

EMACS_BATCH=${EMACS} -Q -batch -L . --eval ${INIT_PACKAGES}

.PHONY: all  test  lint compile clean
all: clean-elc compile lint test

compile: $(ELS)

%.elc: %.el
	$(EMACS) --batch -Q  -L . --eval "(setq byte-compile-error-on-warn t)" \
		--eval "(package-initialize)" \
		-f batch-byte-compile $<

clean-elc:
	rm -f *.elc

clean: clean-elc

TEST_SELECTOR ?= t
test:
	@echo "---- Run unit tests"
	@${EMACS_BATCH} \
		$(addprefix -l ,$(FILES)) \
		$(addprefix -l ,$(TEST_FILES)) \
		--eval "(progn (setq load-prefer-newer t) (ert-run-tests-batch-and-exit '${TEST_SELECTOR}))" \
		&& echo "OK"

checkdoc:
	@for file in $(FILES); do \
		echo "Checking $$file..."; \
		$(EMACS) -Q -L . --batch \
		--eval "(require 'checkdoc)" \
		--eval "(setq checkdoc-sentence-ends-double-space t \
		            checkdoc-proper-noun-list nil \
		            checkdoc-verb-check-experimental-flag nil)" \
		--eval "(let ((ok t)) \
		          (ignore-errors (kill-buffer \"*Warnings*\")) \
		          (let ((inhibit-message t)) \
		            (checkdoc-file \"$$file\")) \
		          (when (get-buffer \"*Warnings*\") \
		            (setq ok nil) \
		            (with-current-buffer \"*Warnings*\" \
		              (message \"%s\" (buffer-string)))) \
		          (unless ok (kill-emacs 1)))" || exit 1; \
	done



package-lint:
	@$(EMACS_BATCH) --eval "(package-initialize)" \
		--eval "(require 'package-lint)" \
		--eval "(setq package-lint-main-file \"helixel.el\")" \
		-f package-lint-batch-and-exit \
		${FILES}


COLWIDTH ?= 80

column-check:
	@echo "---- Check column width <= $(COLWIDTH)"
	@for file in $(FILES); do \
		awk -v w=$(COLWIDTH) \
		'length>w{print FILENAME":"NR": line exceeds "w" columns ("length" chars)"; err=1} END{exit err}' \
		"$$file" || exit 1; \
	done && echo "OK"


lint: compile checkdoc package-lint column-check ctx-lint

# ----------------------------------------------------------------------
# ctx-lint: forbid raw plist-get on sel/ctx — must use helixel-sel-* accessors.
# Only helixel-edit.el (accessor implementations) is exempt.
# ----------------------------------------------------------------------
# ctx-unique keys — any plist-get on these outside helixel-edit.el is forbidden
CTX_UNIQUE = :kind :cursor-offset :moves :command
# suspicious keys — flag for manual review (may be used in other plists)
CTX_SUSPECT = :dir :count :pattern :offset

ctx-lint:
	@echo "---- ctx-lint: raw plist-get on sel/ctx"
	@err=0; \
	for file in $(FILES); do \
	  case "$$file" in helixel-edit.el) continue ;; esac; \
	  for key in $(CTX_UNIQUE); do \
	    if grep -qn "plist-get.*\<$$key\>" "$$file" 2>/dev/null; then \
	      echo "$$file: FATAL — raw plist-get with ctx-unique key $$key:"; \
	      grep -n "plist-get.*\<$$key\>" "$$file"; \
	      err=1; \
	    fi; \
	  done; \
	  for key in $(CTX_SUSPECT); do \
	    matches=$$(grep -n "plist-get.*\<$$key\>" "$$file" 2>/dev/null) || true; \
	    if [ -n "$$matches" ]; then \
	      echo "$$file: REVIEW — plist-get with key $$key (verify it is not ctx):"; \
	      echo "$$matches"; \
	    fi; \
	  done; \
	done; \
	exit $$err
