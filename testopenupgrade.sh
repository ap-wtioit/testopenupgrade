#!/bin/bash
cd $(dirname $0)
BASEDIR=$(pwd)
timestamp=$(date +%s)
database_name="oodo_$timestamp"
database_user=$USER
branch_dir="$(pwd)/upgrades/openupgrade_$timestamp"
#versions[0]=8.0
#versions[1]=9.0
versions[2]=10.0
versions[3]=11.0

#directory to your odoo git repository
ODOO_DIR=../odoo
#local instalation of the OpenUpgrade repository
LOCAL_OPENUPGRADE=../OpenUpgrade
#modules to test the migration
MODULES=base
REMOTE=origin

#preparing openupgrade for local stuff
LOCAL_OPENUPGRADE_REPO="file://$(pwd)/$LOCAL_OPENUPGRADE"
sed -i "s/'url': 'git:\/\/github.com\/OpenUpgrade\/OpenUpgrade.git',/'url': '${LOCAL_OPENUPGRADE_REPO//\//\\/}',/g" $LOCAL_OPENUPGRADE/scripts/migrate.py

for version in ${versions[@]}; do
    echo "Version $version $database_name"
    if psql -ltq | awk -F '\|' '{print $1}' | grep $database_name > /dev/null; then
        echo "Upgrading to version $version"
        cd $LOCAL_OPENUPGRADE
        pwd
        git pull
        pip install -r requirements.txt
        scripts/migrate.py -D $database_name -R $version -C $ODOO_CONFIG -B $branch_dir
        if [ "$?" == "0" ] && ! grep -R ERROR $branch_dir/migration.log 2>&1 ; then
            echo "Upgrade OK"
            database_name="${database_name}_migrated"
            echo "Running Tests"
            if [ -e $branch_dir/$version/server/openerp-server ] ; then
                ODOO_BIN=$branch_dir/$version/server/openerp-server
            else
                ODOO_BIN=$branch_dir/$version/server/odoo-bin
            fi
            cp $ODOO_CONFIG $branch_dir/$version/odoo.cfg
            new_addonspath=$(grep -R addons_path $branch_dir/$version/server.cfg)
            sed 's/^addons_path = .*$/${new_addonspath}/' $branch_dir/$version/odoo.cfg
            echo "root_path = $branch_dir/$version/server" >> $branch_dir/$version/odoo.cfg
            $ODOO_BIN -d $database_name --db_user $USER -u $MODULES --stop-after-init --config $branch_dir/$version/odoo.cfg --test-enable --log-level=test
            result=$?
            if [ "$result" != "0" ] ; then
                echo "Tests failed after upgrade" 1>&2
                exit 4
            fi
        else
            echo "Upgrade failed" 1>&2
            exit 2
        fi
    else
        echo "Installing version $version"
        psql postgres $USER -c "create database $database_name"
        cd $ODOO_DIR
        git fetch
        if ! git checkout $version; then
            git checkout $REMOTE/$version
            git checkout -b $version
        fi
        if [ ! -e $BASEDIR/venv$version ]; then
            virtualenv --python=python2 $BASEDIR/venv$version
            source $BASEDIR/venv$version/bin/activate
            pip install -r requirements.txt
            # fix image.py jpg error: https://stackoverflow.com/questions/8915296/python-image-library-fails-with-message-decoder-jpeg-not-available-pil
            pip install --no-cache-dir -I pillow
        else
            source $BASEDIR/venv$version/bin/activate
        fi
        ODOO_CONFIG="$(pwd)/odoo.conf"
        if [ -e openerp-server ] ; then
            ODOO_BIN=./openerp-server
        else
            ODOO_BIN=./odoo-bin
        fi
        $ODOO_BIN -d $database_name --db_user $USER -i $MODULES --stop-after-init --save
        if [ "$?" == "0" ] ; then
            echo "Install OK, running post install tests"
            # odoo 9.0 loves to generate this config file (which then takes precedence over the given config!)
            if [ -e ~/.openerp_serverrc ] ; then rm ~/.openerp_serverrc; fi
            $ODOO_BIN -d $database_name --db_user $USER -u $MODULES --stop-after-init --config $ODOO_CONFIG --test-enable --log-level=test
            result=$?
            if [ "$result" != "0" ] ; then
                echo "Tests installation failed ($result)" 1>&2
                exit 3
            fi
            cd $BASEDIR
            pwd
        else
            echo "Install failed" 1>&2
            exit 1
        fi
    fi
done