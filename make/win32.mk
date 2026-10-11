# Windows (MinGW-w64 / MSYS2) target.
#
# `base/` produces the native artifacts (the `koreader.exe` launcher, the
# `libs/` shared libraries and the C extension modules under `common/`), and the
# main Makefile already links those into `$(INSTALL_DIR)/koreader` through
# `OUTPUT_DIR_ARTIFACTS`. All that is left to do here is to turn that tree of
# symlinks into a self-contained archive.

# Build the frontend on top of the base build's artifacts.
# Matches `OUTPUT_DIR` in base/Makefile.defs (which adds `-debug` when KODEBUG).
WIN32_BUILD_DIR = $(KOR_BASE)/build/$(MACHINE)

# Run. {{{
PHONY += run

define run_script
for a in $(RARGS); do
    [[ "$$a" = [-/]* ]] || a="$${PWD}/$$a";
    set -- "$$@" "$$a";
done;
cd $(INSTALL_DIR)/koreader && ./koreader.exe "$$@"
endef

run: all
	$(strip $(run_script))
# }}}

# Update/package. {{{
WIN32_PACKAGE = koreader-win32-$(TARGET_MACHINE)$(KODEDUG_SUFFIX)-$(VERSION).zip

update: update-zip

update-zip: all
	# `$(INSTALL_DIR)/koreader` is a tree of symlinks into the build tree and
	# the repo; `zip` follows them, so the archive ends up self-contained.
	# (`-y` would store them as links instead, which Windows cannot use.)
	cd $(INSTALL_DIR) && rm -f ../$(WIN32_PACKAGE)
	cd $(INSTALL_DIR) && zip -qr ../$(WIN32_PACKAGE) koreader
	@echo "[*] Created $(WIN32_PACKAGE)"
	@echo "[*] Run it with: $(INSTALL_DIR)/koreader/koreader.exe"
# }}}

# vim: foldmethod=marker foldlevel=0
