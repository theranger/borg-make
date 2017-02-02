# What to back up and where
BCP_HOST ?= localhost
BCP_USER ?= $(shell hostname)
BCP_NAME ?= {now:%Y-%m-%d}

# MySQL configurable options
MYSQL_USER ?= dump
MYSQL_PASS ?= dumppassword

##############################################################
#                                                            #
#        Usually no need to change stuff below               #
#                                                            #
##############################################################

VERSION := 0.3.0
BCP_DIR := /srv/backup
BRG_BIN := /usr/bin/borg
BRG := $(BRG_BIN) create --compression zlib,9 --umask 0027

MYSQL := /usr/bin/mysql
MYSQLDUMP := /usr/bin/mysqldump
MYSQL_DIR := $(BCP_DIR)/mysql

MONGODUMP := /usr/bin/mongodump
MONGO_DIR := $(BCP_DIR)/mongo

SLAPCAT := /usr/sbin/slapcat
LDAP_DIR := $(BCP_DIR)/ldap

GITLABRAKE := /usr/bin/gitlab-rake


all: help

$(BCP_DIR):
	mkdir -p -m 0700 $@

.PHONY: etc
etc: $(BRG_BIN)
	$(BRG) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) /$@

.PHONY: home
home: $(BRG_BIN)
	$(BRG) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) /$@

.PHONY: opt
opt: $(BRG_BIN)
	$(BRG) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) /$@

.PHONY: srv
srv: $(BRG_BIN)
	$(BRG) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) /$@

$(MYSQL_DIR): $(BCP_DIR)
	mkdir -p $@

$(MONGO_DIR): $(BCP_DIR)
	mkdir -p $@

$(LDAP_DIR): $(BCP_DIR)
	mkdir -p $@

.PHONY: mysqldump
mysqldump: $(MYSQL) $(MYSQLDUMP) $(MYSQL_DIR)
	@for db in $$(echo 'show databases;' | $(MYSQL) -s -u$(MYSQL_USER) -p$(MYSQL_PASS)) ; do \
		echo -n "Backing up $${db}... "; \
		if [ "$${db}" = "information_schema" ] || [ "$${db}" = "performance_schema" ]; then \
			echo " Skipped."; \
		else \
			$(MYSQLDUMP) --opt -u$(MYSQL_USER) -p$(MYSQL_PASS) $${db} | gzip -c > $(MYSQL_DIR)/$${db}.txt.gz; \
			echo "Done."; \
		fi; \
	done

.PHONY: mongodump
mongodump: $(MONGODUMP) $(MONGO_DIR)
	$(MONGODUMP) -o $(MONGO_DIR)

.PHONY: slapcat
slapcat: $(SLAPCAT) $(LDAP_DIR)
	$(SLAPCAT) -l $(LDAP_DIR)/data.ldif

.PHONY: gitlab
gitlab: $(GITLABRAKE)
	$(GITLABRAKE) gitlab:backup:create

dpkg: $(BCP_DIR)
	@dpkg --get-selections > $</dpkg-selections.txt

.PHONY: update
update:
	wget -O Makefile https://raw.githubusercontent.com/theranger/borg-make/master/Makefile

.PHONY: clean
clean:
	rm -rf $(BCP_DIR)

.PHONY: help
help:
	@echo "\nRunning borg-make version: $(VERSION)\n"
	@echo "This is a collection of backup targets to be used with Borg backup tool."
	@echo "To run them, create a cron script in /etc/cron.daily with a command something like:\n"
	@echo "\tmake -C /opt/backup BCP_HOST=<borg-server> MYSQL_PASS=<dump_password> clean etc mysqldump dpkg srv\n\n"
	@echo "To initialize empty repository, use the following command:\n"
	@echo "\tborg init -e none --umask 0027 <BCP_USER>@<BCP_HOST>:<repository>\n"
	@echo "Note, that this script does not support parallel make.\n"
