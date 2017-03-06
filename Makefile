# This file contains sensitive information
# Be sure to use restrictive permissions on it
include Makefile.conf

export BORG_PASSPHRASE=$(BRG_PASSPHRASE)

# What to back up and where
BCP_HOST ?= localhost
BCP_USER ?= $(shell hostname -f)
BCP_NAME ?= {now:%Y-%m-%d}

# MySQL configurable options
MYSQL_USER ?= dump
MYSQL_PASS ?= dumppassword

##############################################################
#                                                            #
#        Usually no need to change stuff below               #
#                                                            #
##############################################################

VERSION := 0.7.1
BCP_DIR := /srv/backup
BRG_BIN := /usr/bin/borg
BRG := $(BRG_BIN) create --compression zlib,9 --umask 0027
BRGINIT := $(BRG_BIN) init --encryption keyfile --umask 0027
BRGSTAT := $(BRG_BIN) info
BRGCHECK := $(BRG_BIN) check -v

SSH := $(shell which ssh)

MYSQL := /usr/bin/mysql
MYSQLDUMP := /usr/bin/mysqldump
MYSQL_DIR := $(BCP_DIR)/mysql

MONGODUMP := /usr/bin/mongodump
MONGO_DIR := $(BCP_DIR)/mongo

SLAPCAT := /usr/sbin/slapcat
LDAP_DIR := $(BCP_DIR)/ldap

GITLABRAKE := /usr/bin/gitlab-rake

 # This must be the same as Gitlab configuration entry gitlab_rails['backup_path'] = '/srv/backup/gitlab'
GITLAB_DIR := $(BCP_DIR)/gitlab
GITLAB_USER := git
GITLAB_GROUP := git


all: help

$(BCP_DIR):
	mkdir -p -m 0700 $@

.PHONY: init
init: $(BRG_BIN)
	$(BRGINIT) $(BCP_USER)@$(BCP_HOST):$(REPO)

.PHONY: lock
lock: $(SSH)
	$(SSH) $(BCP_USER)@$(BCP_HOST) 'mkdir .lock'

.PHONY: unlock
unlock: $(SSH)
	$(SSH) $(BCP_USER)@$(BCP_HOST) 'rm -rf .lock'

.PHONY: etc
etc: $(BRG_BIN)
	$(BRG) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) /$@
	$(BRGSTAT) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat > $@/status.txt'
	$(BRGCHECK) $(BCP_USER)@$(BCP_HOST):$@ 2>&1 | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat >> $@/status.txt'

.PHONY: home
home: $(BRG_BIN)
	$(BRG) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) /$@
	$(BRGSTAT) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat > $@/status.txt'
	$(BRGCHECK) $(BCP_USER)@$(BCP_HOST):$@ 2>&1 | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat >> $@/status.txt'

.PHONY: opt
opt: $(BRG_BIN)
	$(BRG) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) /$@
	$(BRGSTAT) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat > $@/status.txt'
	$(BRGCHECK) $(BCP_USER)@$(BCP_HOST):$@ 2>&1 | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat >> $@/status.txt'

.PHONY: srv
srv: $(BRG_BIN)
	$(BRG) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) /$@
	$(BRGSTAT) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat > $@/status.txt'
	$(BRGCHECK) $(BCP_USER)@$(BCP_HOST):$@ 2>&1 | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat >> $@/status.txt'

$(MYSQL_DIR): $(BCP_DIR)
	mkdir -p $@

$(MONGO_DIR): $(BCP_DIR)
	mkdir -p $@

$(LDAP_DIR): $(BCP_DIR)
	mkdir -p $@

# Gitlab needs special permissions for a backup to succeed
$(GITLAB_DIR): $(BCP_DIR)
	mkdir -p -m 0700 $@
	chown $(GITLAB_USER) $@
	chgrp $(GITLAB_GROUP) $(BCP_DIR)
	chmod g+rx $(BCP_DIR)

.PHONY: mysqldump
mysqldump: $(MYSQL) $(MYSQLDUMP) $(MYSQL_DIR)
	@for db in $$(echo 'show databases;' | $(MYSQL) -s -u$(MYSQL_USER) -p$(MYSQL_PASS)) ; do \
		echo -n "Backing up $${db}... "; \
		if [ "$${db}" = "information_schema" ] || [ "$${db}" = "performance_schema" ]; then \
			echo " Skipped."; \
		else \
			$(MYSQLDUMP) --opt -u$(MYSQL_USER) -p$(MYSQL_PASS) $${db} > $(MYSQL_DIR)/$${db}.sql; \
			echo "Done."; \
		fi; \
	done

.PHONY: mongodump
mongodump: $(MONGODUMP) $(MONGO_DIR)
	$(MONGODUMP) -o $(MONGO_DIR)

.PHONY: slapcat
slapcat: $(SLAPCAT) $(LDAP_DIR)
	$(SLAPCAT) -l $(LDAP_DIR)/data.ldif

# This backup script manages Gitlab backup directory on its own
# Reconfigure Gitlab with gitlab_rails['manage_backup_path'] = false
# Since Borg itself is a backup versioning system, there is no need to keep multiple older Gitlab backups in $(GITLAB_DIR)
.PHONY: gitlab
gitlab: $(GITLABRAKE) $(GITLAB_DIR)
	$(GITLABRAKE) gitlab:backup:create

dpkg: $(BCP_DIR)
	@dpkg --get-selections > $</dpkg-selections.txt

.PHONY: update
update:
	wget -O Makefile https://raw.githubusercontent.com/theranger/borg-make/master/Makefile

.PHONY: update-conf
update-conf:
	wget --backups=1 https://raw.githubusercontent.com/theranger/borg-make/master/Makefile.conf

.PHONY: update-all
update-all: update update-conf

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
	@echo "\tborg init -e keyfile --umask 0007 <BCP_USER>@<BCP_HOST>:<repository>\n"
	@echo "Note, that this script does not support parallel make.\n"
