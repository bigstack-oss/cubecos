# Contributor Covenant Code of Conduct

## Principle

In principle, follow the style and naming conventions of existing code.

## Convention/Style/Scope/Structure

* Uppercase variables are global
* Lowercase variables are local
* Indentation is 4 spaces
* '{' and '}' of a function exist alone in a whole new line
```
cmd()
{
    cmd=$1
    shift 1
    eval "\$$cmd $*"
}
```
* **hex** functions names are camelcase: ```DumpInterfaces()```
* **cube** functions name are lowercase: ```health_k3s_check()```
* files in sdk_sh/modules.pre/ are sourced before those in sdk_sh/module/
* files in sdk_sh/modules.post/ are sourced after those in sdk_sh/module/
* functions inside files in sdk_sh/modules.pre/ are common (reusable) to others
* functions in general are located in a file whose name contains the beginning of the function name
ex: **health**\_link\_report() exists in sdk\_sh/module/sdk\_**health**.sh
* if
```
if [ "x$ERR_CODE" = "x0" ] ; then
fi
```
* for
```
for ip in "${CUBE_NODE_LIST_IPS[@]}" ; do
done
```
* while
```
while ping -c 1 $node >/dev/null ; do
done
```
