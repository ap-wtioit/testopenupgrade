# Testopenupgrade

Script to test if a Odoo module is able to be upgraded with OpenUpgrade

## Prerequesites

## Running

To test upgrading a module just call

```
testopenupgrade.sh {module}
```

## What does the script do?

It ...
1) creates a new directory in the folder upgrades
2) checks out the initial version of odoo
3) installs the corresponding modules to a new database
3) It makes sure that

