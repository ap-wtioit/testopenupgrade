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

python_version[8]=python2
python_version[9]=python2
python_version[10]=python2
python_version[11]=python3

#directory to your odoo git repository
ODOO_DIR=../odoo
#local instalation of the OpenUpgrade repository
LOCAL_OPENUPGRADE=../OpenUpgrade
#modules to test the migration
MODULES=${1:-base}
REMOTE=origin

if [ ! -e upgrades ] ; then mkdir upgrades; fi

#find idea runconfigs
for directory in "." $ODOO_DIR $LOCAL_OPENUPGRADE ; do
    if [ -e $directory/.idea/runConfigurations ] ; then
        IDEA_RUN_CONFIGURATIONS_DIR=$BASEDIR/$directory/.idea/runConfigurations
        echo "Saving idea run configurations to $IDEA_RUN_CONFIGURATIONS_DIR"
    fi
done

#preparing openupgrade for local stuff
LOCAL_OPENUPGRADE_REPO="file://$(pwd)/$LOCAL_OPENUPGRADE"
sed -i "s/'url': 'git:\/\/github.com\/OpenUpgrade\/OpenUpgrade.git',/'url': '${LOCAL_OPENUPGRADE_REPO//\//\\/}',/g" $LOCAL_OPENUPGRADE/scripts/migrate.py

install_version=$(echo ${versions[@]} | awk '{print $1}')
to_version=$(echo ${versions[@]} | awk '{print $NF}')
echo "Testing upgrading module(s) $MODULES from $install_version to $to_version"

function trim() {
    args="$@"
    if [ "${args:0:1}" == " " ]; then
        trim ${args:1}
    elif [ "${args:$((${#@} - 1))}" == " " ] ; then
        trim ${args:0:-1}
    else
        echo $@
    fi
}

function safe_filename() {
    echo $@ | sed 's/[ \\]/_/g'
}

function run_and_save_config() {
    config_name=$1
    cmd=$@
    cmd=$(trim ${cmd:${#config_name}})
    python=$(which python)
    venv=$(dirname $(dirname $(which python)))
    pwd=$(pwd)
    odoo_bin=$(echo "$cmd" | awk '{print $1}')
    parameters=$(trim ${cmd:${#odoo_bin}})

    # save the command in a script related to the config name
    filename=$(safe_filename $branch_dir/$config_name.sh)
    echo -e "#!/bin/bash\ncd $(pwd)\nsource $venv/bin/activate\n$cmd" > $filename
    chmod +x $filename

    # save a .idea run configuration (e.g. for debugging)
    if [ "$IDEA_RUN_CONFIGURATIONS_DIR" != "" ] ; then
        idea_filename=$(safe_filename $IDEA_RUN_CONFIGURATIONS_DIR/${config_name}.xml)
        echo $idea_filename
        for variable in "parameters" "pwd" "config_name" "odoo_bin" "venv"; do
            export $variable="$(eval echo \"\$$variable\")"
        done
        cat $BASEDIR/tpl/python_run_configuration.xml | envsubst > $idea_filename
    fi

    #run the command
    $cmd 2>&1 | tee ../test.log
    result=${PIPESTATUS[0]}
    return $result
}

for version in ${versions[@]}; do
    major_version=${version:0:-2}
    echo "Version $version $database_name"
    if psql -ltq | awk -F '\|' '{print $1}' | grep $database_name > /dev/null; then
        echo "Upgrading to version $version"
        cd $LOCAL_OPENUPGRADE
        git pull
        if [ ! -e $BASEDIR/venv$version ]; then
            virtualenv --python=${python_version[$major_version]} $BASEDIR/venv$version
            source $BASEDIR/venv$version/bin/activate
            pip install -r requirements.txt
            # fix image.py jpg error: https://stackoverflow.com/questions/8915296/python-image-library-fails-with-message-decoder-jpeg-not-available-pil
            #pip install --no-cache-dir -I pillow
        else
            source $BASEDIR/venv$version/bin/activate
        fi
        # force running this script with the python version installed in the virtualenv
        python scripts/migrate.py -D $database_name -R $version -C $ODOO_CONFIG -B $branch_dir
        result=$?
        echo $result
        if [ "$result" == "0" ] && ! grep -R ERROR $branch_dir/migration.log 2>&1 ; then
            echo "Upgrade OK"
            #rename _migrated to _${version}
            psql postgres $USER -c "ALTER DATABASE ${database_name}_migrated RENAME TO ${database_name}_${major_version}"
            data_dir=$(grep -R data_dir $ODOO_CONFIG | awk '{print $3}')
            ln -s $data_dir/filestore/${database_name} $data_dir/filestore/${database_name}_${major_version}
            database_name="${database_name}_${major_version}"
            echo "Running Tests"
            git clone $BASEDIR/$ODOO_DIR --branch $version --single-branch $branch_dir/$version/odoo
            cd $branch_dir/$version/odoo
            if [ -e openerp-server ] ; then
                ODOO_BIN=./openerp-server
            else
                ODOO_BIN=./odoo-bin
            fi

            sed 's/\(openupgrade_[^\/]*\/\)[0-9]*\.[0-9]/\1'$version'/g' $ODOO_CONFIG > $branch_dir/odoo$version.conf

            if [ "${version:0:1}" == "1" ] ; then
                # make sure addons directory points to odoo for versions 10 and 11
                sed -i 's/openerp/odoo/g' $branch_dir/odoo$version.conf
            fi
            run_and_save_config "$database_name postupgrade test" $ODOO_BIN -d $database_name --db_user $USER -u $MODULES --stop-after-init --config $branch_dir/odoo$version.conf --test-enable --log-level=test
            result=$?
            if [ "$result" != "0" ] ; then
                echo "Tests failed after upgrade ($result)" 1>&2
                exit 4
            fi
        else
            echo "Upgrade failed" 1>&2
            exit 2
        fi
    else
        echo "Installing version $version"
        psql postgres $USER -c "create database $database_name"
        git clone $ODOO_DIR --branch $version --single-branch $branch_dir/$version/odoo
        cd $branch_dir/$version/odoo
        if [ ! -e $BASEDIR/venv$version ]; then
            virtualenv --python=${python_version[$major_version]} $BASEDIR/venv$version
            source $BASEDIR/venv$version/bin/activate
            pip install -r requirements.txt
            # fix image.py jpg error: https://stackoverflow.com/questions/8915296/python-image-library-fails-with-message-decoder-jpeg-not-available-pil
            pip install --no-cache-dir -I pillow
        else
            source $BASEDIR/venv$version/bin/activate
        fi
        ODOO_CONFIG="$branch_dir/odoo.conf"
        if [ -e openerp-server ] ; then
            ODOO_BIN=./openerp-server
        else
            ODOO_BIN=./odoo-bin
        fi
        $ODOO_BIN -d $database_name --db_user $USER -i $MODULES --stop-after-init --save --config $ODOO_CONFIG
        # remove web_kanban module from config (it's enterprise)
        sed -i 's/,web_kanban//g' $ODOO_CONFIG
        if [ "$?" == "0" ] ; then
            echo "Install OK, running post install tests"
            run_and_save_config "$database_name postinstall test" $ODOO_BIN -d $database_name --db_user $USER -u $MODULES --stop-after-init --config $ODOO_CONFIG --test-enable --log-level=test
            result=$?
            if [ "$result" != "0" ] ; then
                echo "Tests for installation failed ($result)" 1>&2
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