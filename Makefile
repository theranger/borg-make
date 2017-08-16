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

# Nginx proxy settings for Atlassian software
ATLASSIAN_NGE ?= /etc/nginx/sites-enabled/atlassian
ATLASSIAN_NGA ?= /etc/nginx/sites-available/atlassian
ATLASSIAN_DB ?= atlassian

##############################################################
#                                                            #
#        Usually no need to change stuff below               #
#                                                            #
##############################################################

VERSION := 0.8.0
BCP_DIR := /srv/backup
BRG_BIN := /usr/bin/borg
BRG := $(BRG_BIN) create --compression zlib,9 --umask 0027 $(ARGS)
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

CYRDUMP := /usr/lib/cyrus/bin/ctl_mboxlist
CYRUS_DIR := $(BCP_DIR)/cyrus
CYRUS_USER := cyrus
CYRUS_GROUP := mail

GITLABRAKE := /usr/bin/gitlab-rake

 # This must be the same as Gitlab configuration entry gitlab_rails['backup_path'] = '/srv/backup/gitlab'
GITLAB_DIR := $(BCP_DIR)/gitlab
GITLAB_USER := git
GITLAB_GROUP := git

OC_USER ?= www-data
OC_CMD ?= owncloud/occ
OC := su - $(OC_USER) -c
OC_DB_USER ?= $(shell $(OC) "$(OC_CMD) config:system:get dbuser | tail -n1")
OC_DB_NAME ?= $(shell $(OC) "$(OC_CMD) config:system:get dbname | tail -n1")
OC_DB_PASSWORD ?= $(shell $(OC) "$(OC_CMD) config:system:get dbpassword | tail -n1")
OC_DATA_DIR ?= $(shell $(OC) "$(OC_CMD) config:system:get datadirectory | tail -n1")

PG_DUMP := /usr/bin/pg_dump
PG_DIR := $(BCP_DIR)/postgres
PG_USER := postgres
PG_GROUP := postgres

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

.PHONY: oc_start
oc_start:
	$(OC) "$(OC_CMD) maintenance:mode --on"

.PHONY: oc_end
oc_end:
	$(OC) "$(OC_CMD) maintenance:mode --off"

.PHONY: owncloud
owncloud: $(MYSQLDUMP) oc_start
	$(MYSQLDUMP) -u$(OC_DB_USER) -p$(OC_DB_PASSWORD) $(OC_DB_NAME) > $(OC_DATA_DIR)/$(OC_DB_NAME).sql
	$(BRG) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) $(OC_DATA_DIR)
	$(OC) "$(OC_CMD) maintenance:mode --off"
	$(BRGSTAT) $(BCP_USER)@$(BCP_HOST):$@::$(BCP_NAME) | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat > $@/status.txt'
	$(BRGCHECK) $(BCP_USER)@$(BCP_HOST):$@ 2>&1 | $(SSH) $(BCP_USER)@$(BCP_HOST) 'cat >> $@/status.txt'

.PHONY: atl_start
atl_start: $(ATLASSIAN_NGE)
	rm $(ATLASSIAN_NGE)
	systemctl reload nginx

.PHONY: atl_end
atl_end: $(ATLASSIAN_NGA) $(ATLASSIAN_NGE)
	ln -s $(ATLASSIAN_NGA) $(ATLASSIAN_NGE)
	systemctl reload nginx

.PHONY: atlassian
atlassian: $(PG_DUMP) $(PG_DIR) atl_start
	su - $(PG_USER) -c "$(PG_DUMP) $(ATLASSIAN_DB) > $(PG_DIR)/$(ATLASSIAN_DB).sql"

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

# Cyrus dump needs special permissions for a backup directory
$(CYRUS_DIR): $(BCP_DIR)
	mkdir -p -m 0700 $@
	chown $(CYRUS_USER) $@
	chgrp $(CYRUS_GROUP) $(BCP_DIR)
	chmod g+rx $(BCP_DIR)

# Postgres dump need special permissions for a backup directory
$(PG_DIR): $(BCP_DIR)
	mkdir -p -m 0700 $@
	chown $(PG_USER) $@
	chgrp $(PG_GROUP) $(BCP_DIR)
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

.PHONY: cyrdump
cyrdump: $(CYRDUMP) $(CYRUS_DIR)
	$(CYRDUMP) -d > $(CYRUS_DIR)/mailboxes.dump

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
