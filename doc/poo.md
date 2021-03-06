# Prototype Object Orientation in Gerbil Scheme

This directory implements POO, a system for Prototype Object Orientation,
with a pure lazy functional interface.

Prototypes are the incremental specification of open recursion schemes
that you can either instantiate by computing their fixed point
or extend by composing them together through inheritance.
They embody the essence of both functional and object-oriented programming.

The semantics of POO is very close to the object system of the
[Nix Expression Language](https://nixos.wiki/wiki/Nix_Expression_Language)
(as defined as a library in a few lines in
[`nixpkgs/lib/fixed-points.nix`](https://github.com/NixOS/nixpkgs/blob/master/lib/fixed-points.nix)),
itself essentially identical to that builtin to [Jsonnet](https://jsonnet.org/).
Another influence of note is the [Slate language](https://github.com/briantrice/slate-language).

Pure lazy functional prototype object systems are ideal to incrementally define such things as:
  * configuration for building, installing, and deploying software on a machine or network of machines
    (as used by Nix, NixOS, DisNix, NixOps,
    but also by Jsonnet front-ends to terraform or kubernetes),
  * compile-time representation of objects, types and classes inside a compiler,
  * objects with dynamic combinations of traits that are hard to express in class-based systems.


## Semantics of POO

### The Essence of Computing with POO

In POO, an object, or *poo*, embodies two related but different concepts,
that it is important to distinguish: a *prototype*, and an *instance*.

An *instance* is conceptually a mapping
from *slot names* to values bound to the named slot.
Slot names are typically symbols or string constants.
Each value is the result of a computation specified by the *prototype*;
the value will be computed lazily the first time it is referenced.

A *prototype* is an incremental description of how each slot of an instance
can be computed from (a) the other slots of the instance,
and (b) slot computations *inherited* from some super-prototype.
The inherited slot computations can recursively refer to further inherited slot computations;
while more slots may refer to each other.
When *instantiating* a prototype into an instance,
the resulting instance is the fixed point of all these computations.

A list of prototypes can be combined into a new prototype by *inheritance*.
_Within the scope of this combination_, each prototype in the list is considered
a *super-prototype* of the prototypes appearing earlier in the list,
and a *direct super-prototype* of the prototype appearing immediately before it.
The earlier prototype is said to *inherit from* the super-prototypes,
and to *directly inherit from* its direct super-prototype.
To compute a slot in the combination,
the formula specified by the prototype at the head of the list is used;
if that formula invokes the inherited slot computation, then
the formula for its direct super-prototype is used,
which may in turn invoke the formula from its further direct super-prototype, etc.

If a prototype doesn't specify a slot definition, the result is functionally equivalent to
specifying a slot definition that explicitly just invokes and reuses the inherited slot computation.
If the last prototype in an inheritance list
implicitly or explicitly invokes its inherited slot computation,
then the combined prototype will in turn invoke its direct super-prototype when further combined;
if the prototype is instantiated without further combination, then
an error is raised when a slot is computed that invokes an inherited computation past
the end of the inheritance list.

Note that in the current model, the only way the super-prototype is by invoking
the inherited computation of a slot within the computation of that very same slot:
they are not currently allowed to access a reified "super-instance"
with a notional mapping of slot names to values, or
to access other slots than the current one in that notional mapping.
This allows for notable simplifications in the implementation,
compared to indeed allowing access to such a reified "super-instance",
or to layers of slot bindings, one for each prototype involved in an instance.

In a pure functional lazy setting, all instances of a prototype are the same;
it is appropriate to speak of *the* instance of that prototype, and
to manipulate them together into a single *object*:
when used as part of combinations, the prototype part is used;
when accessing slots, the prototype is implicitly instantiated and the associated instance is used.
A single special form `poo` is used to define an object that simultaneously embodies
a prototype and its instance.

If you use side-effects, it is good discipline (to be enforced in a future version of POO?)
that any prototype used as super-prototype should be immutable
by the time any such combination is instantiated.
To instantiate a prototype `poo` multiple times for the purpose of side-effects,
"just" create a new instance with `(.mix poo)`.

### Further common concepts

A slot computation that doesn't invoke its inherited computation is said to *override* it.
The simplest slot definition is to specify a constant value as the computation,
which will indeed override any inherited computation.

It is not uncommon for a slot computation to always raise an error:
or to be left undefined, which will also implicitly result in an error if accessed:
a further prototype may override this definition, and the error will only be raised
if that default computation is invoked rather than overridden.

A more advanced slot computation may invoke the inherited value and modify it,
for instance increment a count, add one or many elements to a list or set, etc.
The case is common enough that there is a special syntax for when a slot computation
always invokes its inherited computation and modifies its result.

A *method* is a slot the value of which is a function.
The body of the function may or may not use the values of other slots.
The special form `.call` can be used to directly invoke a method.

A *mixin*, or *trait*, is a prototype specifying a partial increment of computation,
referring to slots that it doesn't define, and/or
providing slots that are meant for further use rather than as final values.
Unlike perhaps in other object systems, in POO there is no
technical difference, syntactic distinction, or special semantic treatment,
between prototypes that are or aren't mixins.

Slot computations aren't evaluated until an prototype is instantiated and
the corresponding slot is accessed using the `.ref` function
(or derivative special forms `.call` and `.get`).
Slot computations are thus *lazy*, and may in turn trigger the lazy computation of further slots.
Internally, the implementation uses the standard module `std/lazy` where appropriate.

When incrementally describing a configuration, often a hierarchy of prototypes is defined.
That's where the dual nature of objects as both prototypes and instances becomes really handy:
an object slot may itself contain an object, and so on, and you don't need to track which is which
to recursively instantiate them — every recursive object will be automatically and lazily instantiated
right at the place it is expected when you print or otherwise use the final configuration object.
Internal objects typically contain references back to the surrounding containing object,
from which they can access configuration for parent and sibling configuration objects;
for instance a server's IP address and configuration port will be propagated for use by clients,
that may in turn offer services for use by further clients.
When a mixin adding a service may incrementally refine recursive configuration objects
for many clients and servers...
Beautiful incremental configuration.

### POO Definition Syntax

You can define a *poo* with the special form `.o`
(where the dot is a marker for special POO syntax, where the "o" stands for "object",
and where the syntax is deliberately kept short),
or the special brace syntax (see below), with the following template:

```
(.o [([:: [self [super [extra-slots ...]]]])] slot-definitions ...)
```

The first list of parameters is optional;
it can be omitted, or it can specified as an empty list `()`
to prevent confusion in case you define a macro the users of which
might want to use the keyword `::` as the name of a slot.
In that list:

  * The optional symbol `self` will bound to
    the object being instantiated when the slot values are computed.
    Note that this object may be any object that inherits from the object being currently defined,
    and not necessarily that object itself.

  * The optional value `super` will be used as an object
    or (potentially nested) list of objects
    that the current object will inherit from.
    Specify `[]` for an empty list of objects.

  * The optional list of slot names that follow will be bound to macros
    that will access the relevant slots of the object being instantiated,
    when the slot value is computed. Definitions for these slots
    are presumably to be provided by other prototypes
    in the object being instantiated, since those in the current prototype
    will already be implicitly included in the list of symbols to bind.

Each entry in `slot-definitions` specifies how to compute a given named slot:

  1. When the computation `form` wholly ignores the inherited computation, and *overrides* it,
     the entry is simply:
     ```
     (slot-name form)
     ```

  2. When the computation always invokes the inherited computation and passes it
     to a function `function-form`, to be optionally followed
     by extra arguments `extra-function-args` in the function call,
     the entry is:
     ```
     (slot-name => function-form extra-function-args ...)
     ```

  3. In the more general case that the computation may or may not invoke the inherited computation,
     depending on some condition, then a user-specified symbol will be bound to
     a special form invoking that inherited computation, and the computation `form`
     may use that special form; then the entry is:
     ```
     (slot-name (inherited-computation) form)
     ```

  4. As a short-hand for a common case, a slot may be defined to take the value
     of a same-named variable in the surrounding lexical scope. The entry is simply:
     ```
     (slot-name)
     ```
     or even just
     ```
     slot-name
     ```

  5. As an alternative to a simple `(slot-name spec)`, `(slot-name => spec)` or `(slot-name =>.+ spec)`,
     you can write as a keyword `slot-name:` followed by the `spec`
     with the optional `=>` or `=>.+` before it.
     ```
     slot-name: spec
     slot-name: => spec
     slot-name: =>.+ spec
     ```

As a short-hand, a new variable may be defined and bound to a prototype object with the form:
```
(.def (name [self] [super] [slots ...]) slot-definitions ...)
```
That form is equivalent to `(def name (.o (:: name super slots ...) slot-definitions ...))`.
The `name` can be a simple symbol in which case the options are omitted.

The special brace syntax is available if you `(import :clan/poo/brace)`
and overrides the `{}` syntax of Gerbil so that `{spec ...}` is the same as `(.o spec ...)`.
Note that this works by overriding the binding of the special symbol `@method`,
and that to define or use Gerbil methods, you will have to use `(@@method x ...)`
where you previously would have used `{x ...}` or `(@method x ...)`.


### POO Usage Syntax

To combine any number of objects or recursive list of objects using inheritance,
use the function `.mix`:
```
(.mix poo1 [poo2 [poo3 poo4] poo5] poo6 [] poo7)
```

To refer to a slot in an object, use the function `.ref`:
```
(.ref poo 'x)
```

To access a slot named by a constant symbol, use the macro `.get` as short-hand:
```
(.get poo x)
```
The macro also works with any constant object for a name;
if multiple names are specified, the names are used in sequence
to recursively access slots of nested objects:
```
(.get poo x y z)
```

You can recognize whether an object is POO with `poo?`
```
(assert-equal! (poo? (.o (x 1) (y 2))) #t)
(assert-equal! (poo? 42) #f)
```

Two special forms allow for side-effects, breaking the pure functional interface — use with caution.
The `.def` form adds a slot definition after the fact to an existing object prototype,
without changing the instance; it will only affect instances using the prototype
if they haven't used the previous definition yet.
```
(.def foo (x 1))
(.def! foo y (x) (+ x 3))
(assert-equal! (.get foo y) 4)
```

The `.set!` form modifies the value of an object instance without changing the prototype.
```
(.def bar (x 1))
(assert-equal! (.get bar x) 1)
(.set! bar x 18)
(assert-equal! (.get bar x) 18)
```

For reflection on what slots an object does or doesn't define, two functions are available:
```
(assert-equal! (.key? foo 'y) #t)
(def (sort-symbols symbols) (sort symbols (λ (a b) (string< (symbol->string a) (symbol->string b)))))
(assert-equal! (sort-symbols (.all-slots foo)) '(x y))
```

A short-hand for one or multiple nested checks of `.key?` with unquoted key is available:
```
(.def baz (a (.o (b (.o (c 1))))))
(assert-equal! (.has? baz a b c) #t)
(assert-equal! (.has? baz a d) #f)
```

## Examples

### Simple definitions and usage

The following form defines a point with two coordinates `x` and `y`;
the first three empty lists stand for the omitted `self` variable,
the empty list of super-prototypes, and the empty list of extra slots:
```
(def my-point (.o (x 3) (y 4)))
```
Similarly, here is a prototype object for a colored object,
using the short-hand `.def` special form:
```
(.def blued (color 'blue))
```
The two can be combined in a single object using the function `.mix`:
```
(def my-colored-point (.mix blued my-point))
```
You can verify that the slots have the expected values:
```
(assert-equal! (.ref my-colored-point 'x) 3)
(assert-equal! (.ref my-colored-point 'y) 4)
(assert-equal! (.ref my-colored-point 'color) 'blue)
```
You could use `.get` instead of `.ref` to skip a quote:
```
(assert-equal! (.get my-colored-point x) (.ref my-colored-point 'x))
```

### Simple mixins

This mixin defines (using `.o` syntax) a complex number `x+iy`
for an object that with slots `x` and `y`,
to be defined in a different mixin (note the use of `@` as an unused symbol for self):
```
(def complex (.o (:: @ [] x y) (x+iy (+ x (* 0+1i y)))))
```
And this mixin defines (using `.def` syntax) polar coordinates for an object with a slot `x+iy`:
```
(.def (polar @ [] x+iy) (rho (magnitude x+iy)) (theta (angle x+iy)))
```
You can mix these together and see POO at work:
```
(assert-equal! (.get (.mix colored-point polar complex) rho) 5)
```

### More advanced slot definitions

A slot defined from the lexical scope:
```
(let ((x 1) (y 2))
  (.def point (x) (y))
  (assert-equal! (map (cut .ref point <>) '(x y)) [1 2]))
```

A slot defined by modifying the inherited value:
```
(.def gerbil-config
  (modules => prepend '(gerbil gambit)))
(def (prepend x y) (append y x))
(.def base-config
  (modules '(kernel stdlib init)))
(assert-equal! (.get (.mix gerbil-config base-config) modules)
               '(gerbil gambit kernel stdlib init))
```

A slot defined by conditionally using the inherited computation:
```
(.def (hello @ [] name)
  (language 'en)
  (greeting (format greeting-fmt name))
  (greeting-fmt "hello, ~a"))
(defpoo (localize-hello @ [hello] language)
  (name "poo")
  (greeting-fmt (next) (if (eq? language 'fr) "salut, ~a" (next))))
(defpoo (french-hello @ localize-hello)
  (language 'fr))
(assert-equal! (.get localize-hello greeting) "hello, poo")
(assert-equal! (.get french-hello greeting) "salut, poo")
```

### Further examples

There are more examples are in the file [`poo-test.ss`](tests/poo-test.ss).

## Future Features

In the future, we may add the following features:

  * Redefine POO in a more compositional way, with a builtin MOP.
    https://github.com/fare/projects/issues/7
    Start from something minimal, in the spirit of the 99-character functions
    ```
    (define (make p b) (letrec ((f (p (λ a (apply f a)) b))) f))
    (define ((inhr p q) f s) (p f (q f s)))
    ```
    Maybe a record that caches together both the prototype function and its lazy fixed point,
    together with a meta-object, itself a prototype that describes how instantiation and composition work,
    as well as additional type-specific accessors or extension points, encoding information, etc.
    ```
    (defstruct poo (meta prototype instance) constructor: :init!)
    ```
    We might want to make "meta" part of the prototype and of the instance, but then
    this already supposes some fixed magic record structure in said prototype or instance,
    which gets into the way of some nice algebraic composable structure for said prototype or instance,
    unless made separable in a way that becomes isomorphic to the above, just with extra steps.
    With a separate meta-object, we can compositionally build up the meta-object
    to refine how the prototypes are instantiated and composed, how they can be built in terms
    of "extension points" each of which will be its own prototype, etc.
    With "objects", an extension point is further refined to specify a record of extension points;
    with "method combinations", some extension point will control the flattening of individual prototypes;
    with "prototype linearization", super prototypes are a dependency graph, not a mere list,
    and a list is first extracted from that graph (based on some external global well-ordering
    of all prototypes?).
    The "object" reference would provide context for the lazy evaluation of whatever "attributes"
    (each the cached computed fixed-point value of some "extension point"), etc.

  * Maybe improve the object definition syntax using keywords, as in e.g.
    `(.o self: self super: super inherit: [supers ...] bind: (x y z) bind-these: #t (slot forms) ...)`
    To implement it with `syntax-case`, see e.g. these definitions for [defproto](https://github.com/vyzo/gerbil/blob/ee22de628a656ee59c6c72bc25d7b2e25a4ece2f/src/std/actor/proto.ss#L261) and [defhandler](https://github.com/belmarca/gerbil-fwd/blob/83120eac03fa39338c82993d3041ddad01432419/fwd/routing.ss#L65).

  * Make it optional whether to include the currently-defined slots in the list of slots to be bound.

  * Constraint-checking assertions and other instantiation-time side-effects
    as part of the `.instantiate` function.

  * A library for class-based object orientation using POO as its meta-object protocol (MOP):
    the same descriptor meta-object, viewed as a prototype is a class descriptor,
    and viewed as an instance is a type descriptor.
    Its element template prototype can specify provide default slot values
    as well as constraints on slot types and slot values.

  * Constraint-checking assertions and other instantiation-time side-effects,
    and a function `.instantiate` to invoke them without accessing a slot.

  * Enforcement of a discipline on prototype mutability.
    Objects must not be modified after having been used as super-prototypes.

  * Reflection on objects, to view a list of slots, to intercept how slots are computed,
    or determine who has access to which slots when.

  * Support for conditionally-defined slots, or slots for computed names.

  * Support for slot definition macros with non-local effects to the rest of the object,
    e.g. to declare a slot as "public" or "private",
    and have that reflected in a list of either kind of slots, and/or in slot-property meta-slot;
    similarly, slot combination methods as meta-information, similar to method combination in CLOS.

  * A better implementation of Jsonnet and/or Nix in Gerbil, based on POO (?)

  * Design and implement a type system that works well with POO.
    https://github.com/fare/projects/issues/3
    This type system probably would have some notion of subtyping, such that
    a function prototype has type `(forall a (forall b < a (b <- (b <- a) <- a)))`.


## Implementation Notes

### Current internals

Internally, in the current implementation, an object, or poo, is `Poo` struct, with two slots:
a list of elementary prototypes and an instance.

Each elementary prototype is a hash-table mapping each defined slot name to a function
that computes the slot value from two arguments:
  1. a reference to the object itself,
  2. the list of super-prototypes.

The instance is a hash-table mapping for each slot name the value computed
by using the prototypes, or otherwise explicitly set as a side-effectful override.

Note that this model is not capable of supporting a slightly more expressive object model
where computations can access arbitrary slots of the super-object,
or a reified version of the super-object itself.
If such an extension is considered useful, it may be implemented by resurrecting
a notion of "layers" present in a previous version of the code, wherein each instance
contains a list of layers, one for each prototype in the list, that maps slot names to values
for the definitions present in that given prototype.
The first layer can also serve to cache all slot computations and
hold values of slots modified by side-effects.

### Internals TODO

  * Implement a proper inheritence DAG with a list of super-prototypes from which a
    prototype-precedence list is deduced, rather than require the user to supply the precedence list.

  * Represent prototypes as pure persistent maps, instead of hash-tables and/or lists thereof?
    Merge them in a way that maximizes sharing of state, maybe even with hash-consing.

  * Represent the instance (or its base layer, if there are many layers) as a vector,
    wherein the indexes are based on the hash-consed "shape" of the prototype,
    the shape being the sorted list of its slot names.

  * Combine the two above optimizations with a third, wherein any name used in a prototype
    is assigned a unique integer number (based on tree walking the entire program?), and
    hash-consed word-granular (rather than bitwise) patricia tree datastructures are used for shapes.

  * Better debugging for circular definitions with a variant of hash-ensure-ref that detects them.

  * Make sure this works well with constant-folding in the underlying compiler.

  * Look at Squeak Traits and/or its descendant Perl 6 object
    for how they linearize inheritance hierarchies.
    Each prototype or class can choose how it linearizes its super-objects.

  * In Slate a mixin is an object with behavior and no state.
    In Squeak, a Trait has a protocol that has modular requirements and provisions.
    Records, delegation. Object/Meta delegation flag attached to the slot.
    e.g. for "new", you want a new object, not a new class.
    Primitives: method lookup, method lookup after (from some point in the hierarchy).
    method-not-found catch-all.
    Multimethod dispatch: the earlier arguments would take priority over later one for method-not-found;
    in DSLs, the method-not-found would do autodiscovery from e.g. the filesystem.
    Subjective dispatch vs objective dispatch.
    Performance: Method inline caching.

  * Look what we can save from [TinyCLOS](https://github.com/ultraschemer/gambit-tiny-clos/blob/master/tiny-clos/core.scm) ?
