TOP_DIR = ../..
include $(TOP_DIR)/tools/Makefile.common

DEPLOY_RUNTIME ?= /kb/runtime
TARGET ?= /kb/deployment

SRC_CGI_PERL = $(wildcard cgi-scripts/*.pl)
BIN_CGI_PERL = $(addprefix $(CGI_BIN_DIR)/,$(basename $(notdir $(SRC_CGI_PERL))))

SRC_PERL = $(wildcard scripts/*.pl)
BIN_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_PERL))))
DEPLOY_PERL = $(addprefix $(TARGET)/bin/,$(basename $(notdir $(SRC_PERL))))

SRC_SERVICE_PERL = $(wildcard service-scripts/*.pl)
BIN_SERVICE_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_SERVICE_PERL))))
DEPLOY_SERVICE_PERL = $(addprefix $(SERVICE_DIR)/bin/,$(basename $(notdir $(SRC_SERVICE_PERL))))

C_PROGS = 

SRC_C = $(addprefix scripts/,$(C_PROGS))
BIN_C = $(addprefix $(BIN_DIR)/,$(C_PROGS))
DEPLOY_C = $(addprefix $(TARGET)/bin/,$(C_PROGS))

PERL = $(KB_RUNTIME)/bin/perl
CC =  $(shell $(PERL) -e 'use Config; print $$Config{cc}')
CFLAGS = $(shell $(PERL) -e 'use Config; print "$$Config{ccflags} -I$$Config{archlib}/CORE -I$(KB_RUNTIME)/lib/perl5/$$Config{version}/$$Config{archname}/CORE"') -O -lm

CLIENT_TESTS = $(wildcard t/client-tests/*.t)
SERVER_TESTS = $(wildcard t/server-tests/*.t)
PROD_TESTS = $(wildcard t/prod-tests/*.t)

STARMAN_WORKERS = 8
STARMAN_MAX_REQUESTS = 100

TPAGE_ARGS = --define kb_top=$(TARGET) --define kb_runtime=$(DEPLOY_RUNTIME) --define kb_service_name=$(SERVICE) \
	--define kb_service_port=$(SERVICE_PORT) --define kb_service_dir=$(SERVICE_DIR) \
	--define kb_sphinx_port=$(SPHINX_PORT) --define kb_sphinx_host=$(SPHINX_HOST) \
	--define kb_starman_workers=$(STARMAN_WORKERS) \
	--define kb_starman_max_requests=$(STARMAN_MAX_REQUESTS) \
	--define dbms=$(DBMS) \
	--define db=$(DB) \
	--define dbhost=$(DBHOST) \
	--define dbuser=$(DBUSER) \
	--define dbpass=$(DBPASS)

all: bin cp-html cp-templates

bin: $(BIN_PERL) $(BIN_SERVICE_PERL) $(BIN_CGI_PERL)

cp-html: 
	mkdir -p $(TOP_DIR)/html
	rsync -arv {js,images,css}/* $(TOP_DIR)/html

cp-templates:
	mkdir -p $(TOP_DIR)/lib/templates
	rsync -arv templates/* $(TOP_DIR)/lib/templates

.PHONY: fig_config clean

clean:
	rm lib/FIG_DB_Config.pm

fig_config: lib/FIG_DB_Config.pm

lib/FIG_DB_Config.pm: FIG_DB_Config.pm.tt Makefile
ifeq ($(DB),)
	@echo "DB was not set" 2>&1; exit 1
endif
	$(TPAGE) $(TPAGE_ARGS) FIG_DB_Config.pm.tt > lib/FIG_DB_Config.pm

$(BIN_DIR)/index_contig_files: scripts/index_contig_files.c scripts/md5.c
	$(CC) $(CFLAGS) -o $@ $^

deploy: deploy-all
deploy-all: deploy-client 
deploy-client: deploy-libs deploy-scripts deploy-docs
deploy-service: deploy-libs deploy-scripts deploy-cgi-scripts deploy-service-scripts deploy-docs

deploy-service-scripts:
	export KB_TOP=$(TARGET); \
	export KB_RUNTIME=$(DEPLOY_RUNTIME); \
	export KB_PERL_PATH=$(TARGET)/lib ; \
	for src in $(SRC_SERVICE_PERL) ; do \
	        basefile=`basename $$src`; \
	        base=`basename $$src .pl`; \
	        echo install $$src $$base ; \
	        cp $$src $(TARGET)/plbin ; \
	        $(WRAP_PERL_SCRIPT) "$(TARGET)/plbin/$$basefile" $(TARGET)/services/$(SERVICE)/bin/$$base ; \
	done

deploy-cgi-scripts:
	export KB_TOP=$(TARGET); \
	export KB_RUNTIME=$(DEPLOY_RUNTIME); \
	export KB_PERL_PATH=$(TARGET)/lib ; \
	for src in $(SRC_CGI_PERL) ; do \
	        basefile=`basename $$src`; \
	        base=`basename $$src .pl`; \
	        echo install $$src $$base ; \
	        cp $$src $(TARGET)/plbin ; \
	        $(WRAP_PERL_SCRIPT) "$(TARGET)/plbin/$$basefile" $(TARGET)/cgi-bin/$$base ; \
	done


deploy-dir:
	if [ ! -d $(SERVICE_DIR) ] ; then mkdir $(SERVICE_DIR) ; fi
	if [ ! -d $(SERVICE_DIR)/bin ] ; then mkdir $(SERVICE_DIR)/bin ; fi

deploy-docs: 


clean:

$(BIN_DIR)/%: scripts/%.c
	$(CC) $(CFLAGS) -o $@ $<

$(BIN_DIR)/%: service-scripts/%.pl $(TOP_DIR)/user-env.sh
	$(WRAP_PERL_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

$(CGI_BIN_DIR)/%: cgi-scripts/%.pl $(TOP_DIR)/user-env.sh
	$(WRAP_PERL_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@.cgi

$(BIN_DIR)/%: service-scripts/%.py $(TOP_DIR)/user-env.sh
	$(WRAP_PYTHON_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

include $(TOP_DIR)/tools/Makefile.common.rules
