SHELL=/bin/bash -c 'set -eo pipefail; [[ -f environment ]] && source environment; shift; eval $$@' $@
GH_AUTH_FILE=~/.github_token
CLEAN_DIRS=aegea

release_major:
	$(eval export TAG=$(shell git describe --tags --match 'v*.*.*' | perl -ne '/^v(\d)+\.(\d)+\.(\d+)+/; print "v@{[$$1+1]}.0.0"'))
	$(MAKE) release

release_minor:
	$(eval export TAG=$(shell git describe --tags --match 'v*.*.*' | perl -ne '/^v(\d)+\.(\d)+\.(\d+)+/; print "v$$1.@{[$$2+1]}.0"'))
	$(MAKE) release

release_patch:
	$(eval export TAG=$(shell git describe --tags --match 'v*.*.*' | perl -ne '/^v(\d)+\.(\d)+\.(\d+)+/; print "v$$1.$$2.@{[$$3+1]}"'))
	$(MAKE) release

release:
	@if [[ -z $$TAG ]]; then echo "Use release_{major,minor,patch}"; exit 1; fi
	$(eval REMOTE=$(shell git remote get-url origin | perl -ne '/(\w+\/\w+)[^\/]+$$/; print $$1'))
	$(eval GIT_USER=$(shell git config --get user.email))
	$(eval GH_AUTH=$(shell if [[ -e $(GH_AUTH_FILE) ]]; then echo $(GIT_USER):$$(cat $(GH_AUTH_FILE)); else echo $(GIT_USER); fi))
	$(eval RELEASES_API=https://api.github.com/repos/${REMOTE}/releases)
	$(eval UPLOADS_API=https://uploads.github.com/repos/${REMOTE}/releases)
	git clean -x --force ${CLEAN_DIRS}
	TAG_MSG=$$(mktemp); \
	    echo "# Changes for ${TAG} ($$(date +%Y-%m-%d))" > $$TAG_MSG; \
	    git log --pretty=format:%s $$(git describe --abbrev=0)..HEAD >> $$TAG_MSG; \
	    $${EDITOR:-emacs} $$TAG_MSG; \
	    if [[ -f Changes.md ]]; then cat $$TAG_MSG <(echo) Changes.md | sponge Changes.md; git add Changes.md; fi; \
	    if [[ -f Changes.rst ]]; then cat <(pandoc --from markdown --to rst $$TAG_MSG) <(echo) Changes.rst | sponge Changes.rst; git add Changes.rst; fi; \
	    git commit -m ${TAG}; \
	    git tag --sign --annotate --file $$TAG_MSG ${TAG}
	git push --follow-tags
	http --auth ${GH_AUTH} ${RELEASES_API} tag_name=${TAG} name=${TAG} \
	    body="$$(git tag --list ${TAG} -n99 | perl -pe 's/^\S+\s*// if $$. == 1' | sed 's/^\s\s\s\s//')"
	$(MAKE) install
	http --auth ${GH_AUTH} POST ${UPLOADS_API}/$$(http --auth ${GH_AUTH} ${RELEASES_API}/latest | jq .id)/assets \
	    name==$$(basename dist/*.whl) label=="Python Wheel" < dist/*.whl

pypi_release:
	python setup.py sdist bdist_wheel upload --sign

.PHONY: release