PREFIX ?= $(HOME)/.local

check:
	./test

install:
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	install -C -m 755 lord $(DESTDIR)$(PREFIX)/bin/lord

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/lord

.PHONY: check test install uninstall
test: check
