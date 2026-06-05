EMACS ?= emacs

FILES = helixel-core.el helixel-ring.el helixel-macros.el helixel-insert-record.el helixel-repeat.el helixel-chain.el helixel-state.el helixel-move.el helixel-keymap.el helixel-search.el helixel-editing.el helixel-surround.el helixel-swap.el helixel-textobj-engine.el helixel-textobj-pair.el helixel-textobj-block.el helixel-textobj-marks.el helixel-textobj.el helixel-mc-core.el helixel-mc-targets.el helixel-mc-spawn.el helixel-mc-integrate.el helixel-shims.el helixel.el
ELS := helixel-core.elc helixel-ring.elc helixel-macros.elc helixel-insert-record.elc helixel-repeat.elc helixel-chain.elc helixel-state.elc helixel-move.elc helixel-keymap.elc helixel-search.elc helixel-editing.elc helixel-surround.elc helixel-swap.elc helixel-textobj-engine.elc helixel-textobj-pair.elc helixel-textobj-block.elc helixel-textobj-marks.elc helixel-textobj.elc helixel-mc-core.elc helixel-mc-targets.elc helixel-mc-spawn.elc helixel-mc-integrate.elc helixel-shims.elc helixel.elc

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

.PHONY: all  test  lint compile clean depgraph
all: clean-elc compile lint test

compile: $(ELS)

%.elc: %.el
	$(EMACS) --batch -Q  -L . --eval "(setq byte-compile-error-on-warn t)" \
		--eval "(package-initialize)" \
		-f batch-byte-compile $<

clean-elc:
	rm -f *.elc

clean: clean-elc

run:
	emacs -Q -L . -l helixel.el --eval '(helixel-mode)'

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
		${FILES} 2>&1; rc=$$?; \
	  if [ $$rc -gt 1 ]; then exit $$rc; fi


COLWIDTH ?= 80

column-check:
	@echo "---- Check column width <= $(COLWIDTH)"
	@for file in $(FILES); do \
		awk -v w=$(COLWIDTH) \
		'NR>1 && length>w{print FILENAME":"NR": line exceeds "w" columns ("length" chars)"; err=1} END{exit err}' \
		"$$file" || exit 1; \
	done && echo "OK"


lint: compile checkdoc package-lint column-check ctx-lint

depgraph:
	@emacs --batch -Q --script scripts/gen-depgraph.el > docs/DEPGRAPH.md
	@echo "docs/DEPGRAPH.md regenerated"

# ----------------------------------------------------------------------
# ctx-lint: forbid raw plist-get on sel/ctx — must use helixel-sel-* accessors.
# ----------------------------------------------------------------------
# ctx-unique keys — any plist-get on these outside helixel-core.el is forbidden
CTX_UNIQUE = :kind :cursor-offset :moves :command
# suspicious keys — flag for manual review (may be used in other plists)
CTX_SUSPECT = :dir :count :pattern :offset

ctx-lint:
	@echo "---- ctx-lint: raw plist-get on sel/ctx"
	@err=0; \
	for file in $(FILES); do \
	  case "$$file" in helixel-core.el) continue ;; esac; \
	  for key in $(CTX_UNIQUE); do \
	    if grep -qnE "plist-get.*$$key([^a-zA-Z0-9_-]|$$)" "$$file" 2>/dev/null; then \
	      echo "$$file: FATAL — raw plist-get with ctx-unique key $$key:"; \
	      grep -nE "plist-get.*$$key([^a-zA-Z0-9_-]|$$)" "$$file"; \
	      err=1; \
	    fi; \
	  done; \
	  for key in $(CTX_SUSPECT); do \
	    if grep -qn "plist-get.*$$key" "$$file" 2>/dev/null; then \
	      MATCHES=$$(grep -n "plist-get.*$$key" "$$file" \
	                | grep -v "helixel--active-search" \
	                | grep -v "helixel-edit-payload" \
	                | grep -v "ctx-lint-ok"); \
	      if [ -n "$$MATCHES" ]; then \
	        echo "$$file: REVIEW — plist-get with key $$key (verify it is not ctx):"; \
	        echo "$$MATCHES"; \
	      fi; \
	    fi; \
	  done; \
	  if grep -qn "plist-get (helixel-edit-payload" "$$file" 2>/dev/null; then \
	    echo "$$file: FATAL — raw plist-get on helixel-edit-payload; use helixel-edit-payload-get:"; \
	    grep -n "plist-get (helixel-edit-payload" "$$file"; \
	    err=1; \
	  fi; \
	done; \
	exit $$err
