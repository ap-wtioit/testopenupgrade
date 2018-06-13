# Testopenupgrade

Script to test if a Odoo module is able to be upgraded with [OpenUpgrade](https://github.com/OCA/OpenUpgrade)

## Prerequesites

checkout [odoo](https://github.com/odoo/odoo), [OpenUpgrade](https://github.com/OCA/OpenUpgrade) and [testopenupgradelib](https://github.com/ap-wtioit/testopenupgradelib) in a directory next to each other:

```bash
git clone https://github.com/odoo/odoo/
git clone https://github.com/OCA/OpenUpgrade/
git clone https://github.com/ap-wtioit/testopenupgradelib/
```

Also you need to have python 2, python 3 and postgres installed


## Running

To test upgrading a module just call

```
testopenupgrade.sh {module}
```

## What does the script do?

It ...
0) creates a new directory in the folder upgrades
0) checks out the initial version of odoo
0) installs the corresponding modules to a new database
0) makes sure that the tests pass in clean odoo
0) performs open upgrade to the next version
0) runs the test for this version
0) repeats the previous 2 steps until target version is reached or something fails

