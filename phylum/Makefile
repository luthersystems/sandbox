PROJECT_REL_DIR:=..
include ${PROJECT_REL_DIR}/common.mk

SOURCE_FILES=$(shell find . -name "*.lisp" | grep -v '/build')

PHYLUM_NAME=${PROJECT}.zip
PHYLUM_PATH=build/${PROJECT}-${BUILD_VERSION}/${PHYLUM_NAME}

SHIRO_TEST=${DOCKER_RUN} -v ${PHYLUMDIR}:/tmp -w /tmp ${SHIROTESTER_IMAGE} unit-tests --verbose .

# This is an unfortunate hack to get around DnD mounts which must
# be relative to the host machine.
PHYLUMDIR?=${CURDIR}
PHYLUM_PACKAGE=${PROJECT}

.PHONY: default
default: build

.PHONY: build
build: ${PHYLUM_PATH}

.PHONY: clean
clean:
	rm -rf build

.PHONY: test
test: go-test shiro-test
	@

.PHONY: go-test
go-test:
	go test -v -race -cover ./...

.PHONY: shiro-test
shiro-test: build
	${SHIRO_TEST}

.PHONY: repl
repl:
	${DOCKER_RUN} -it \
		-v ${PHYLUMDIR}:/tmp \
		-w /tmp \
		${SHIROTESTER_IMAGE} \
		repl --in-package ${PHYLUM_PACKAGE} .

${PHYLUM_PATH}: ${SOURCE_FILES}
	mkdir -p $(dir $@)
	cp $^ $(dir $@)
	sed -i='.orig' "s/LUTHER_PROJECT_VERSION/${VERSION}/" $(dir $@)/main.lisp
	sed -i='.orig' "s/LUTHER_PROJECT_BUILD_ID/${BUILD_ID}/" $(dir $@)/main.lisp
	cd $(dir $@) && ls && zip $(notdir $@) $^

.PHONY: phylum-path
phylum-path:
	@echo ${PHYLUM_PATH}

.PHONY: format
format: ${SOURCE_FILES}
	yasi --no-exit --no-backup --no-warning --no-output --indent-comments --uniform --default-indent 2 --dialect clojure $^;

# print out make variables, e.g.:
# make echo:VERSION
echo\:%:
	@echo $($*)
