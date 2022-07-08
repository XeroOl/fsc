# fsc
A custom """programming language""" that compiles to Lua. It is based on the programming language Fennel.
Requires linux or mac, and needs fennel on the path.

Install:
```sh
git clone git@github.com:XeroOl/fsc.git
cargo install --path fsc
```

Usage:
```sh
# help
fsc --help
# compile to lua
fsc file.fsc > out.lua
# compile to fennel
fsc file.fsc --fennel > out.fnl
```

Example:
```
# declare variables with `let`
let mynumber = 10

# variable names can have anything in them, like lisp
# true, false, and nil are special
# [] for table declarations
# no separators for tables
let builtin-items = [true false nil]

# {} for key-value tables
let j = {

    # keys go on the left of the expression, values on the right
    # key is "x", value is 1
    x = 1

    # you can quote keys if they contain special characters
    # key is "my key with a space", value is 5
    "my key with a space" = 5

    # if the key is in scope, you don't need to specify the value
    # key is "mynumber", value is 10
    mynumber

    # if the key is supposed to be a variable or an expression, wrap in []
    ["my key" .. " that is an expression"] = builtin-items
}

# Function declarations
# the function is named "greet", and takes an argument called "name"
# F# style function declarations and calls
let greet name =
    print ("Hello " .. name .. "!")

# If expressions/statements with `if`, `elseif`, and `else`
# functions return by their tail expression
# there is no "return" keyword
let fib x =
    if (x <= 1)
        1
    else
        fib (x - 1) + fib (x - 2)

# if statements need parentheses for expressions, but not for variables
# This is because the ()'s are actually a function call
let fsc-makes-sense = false

if fsc-makes-sense
    print "cool"
else
    print "oh no"

# the whole language is really cursed, and it's a lisp
print (+ 1 (* 2 3))


# semicolon makes a no-argument function
let run-function; =
    print "the function has executed"

# calls look the same way
run-function;

# since it's secretly a lisp, parens also call a no arg function
(run-function)
# or a regular function
(fib 10)

# iterator style loop
for i v in (ipairs builtin-items)
    print i v

# numeric style loop
# for name = (start end step)
for i = (1 10 2)
    print i


# pattern matching
let [x y] = [1 2]

# match statements
match [x y]
    [1 1]
        print "it was 1 1"
    ([1 z] where (z > 10))
        print ("it was 1 " .. z)
    [a b]
        print ("it was " .. a .. " " .. b)
    _
        print "it was something else" 

# macros
# doesn't support ` and , reader macros, but you can use `quote` and `unquote` and `sym` and `list` and stuff from fennel
macro cursed a b =
    quote ((unquote b) (unquote a))

cursed 10 print

print "threading macros"
    -> 1
        + 2
        * 3


# call methods with ' sugar
# in addition to whatever magic fennel has
print ('sub "mystring" 1 2)
print (: "mystring" :sub 1 2)
let s = "mystring"
print (s:sub 1 2)

# at the end of your module, you list all the things you want to expose from your module
# other modules can require your module to get these things
{
    run-function
    builtin-items
    greet
}
```
