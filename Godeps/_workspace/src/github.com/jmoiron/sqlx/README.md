#sqlx

[![Build
Status](https://drone.io/github.com/jmoiron/sqlx/status.png)](https://drone.io/github.com/jmoiron/sqlx/latest)
[![Godoc](http://img.shields.io/badge/godoc-reference-blue.svg?style=flat)](https://godoc.org/github.com/jmoiron/sqlx)

sqlx is a library which provides a set of extensions on go's standard
`database/sql` library.  The sqlx versions of `sql.DB`, `sql.TX`, `sql.Stmt`,
et al. all leave the underlying interfaces untouched, so that their interfaces
are a superset on the standard ones.  This makes it relatively painless to
integrate existing codebases using database/sql with sqlx.

Major additional concepts are:

* Marshal rows into structs (with embedded struct support), maps, and slices
* Named parameter support including prepared statements
* `Get` and `Select` to go quickly from query to struct/slice
* `LoadFile` for executing statements from a file

There is now some [fairly comprehensive documentation](http://jmoiron.github.io/sqlx/) for sqlx.
You can also read the usage below for a quick sample on how sqlx works, or check out the [API
documentation on godoc](http://godoc.org/github.com/jmoiron/sqlx).

## Recent Changes

There have been some recent changes to the sqlx API after a long period of
API stability.  These changes were made for a number of reasons:

* the API surface area was way too large
* descending non-embedded structs was confusing and problematic
* separating map/struct for binding added lots of noise and little value
* reflect helpers didn't belong in the API of `sqlx`

Towards this end, the following public API has been removed or altered:

* **Execl**, **Execf**, **Execv**, **Selectf**, and **Selectv** removed.
* **Execp** removed in favor of `MustExec`, which remains.
* **BindMap**, **BindStruct** removed in favor of **BindNamed** which handles
  both maps and structs.
* **NamedExecMap**, **NamedQueryMap** removed in favor of **NamedExec** and
  **NamedQuery**, respectively, which both handle structs & maps.
* **Binder** interface no longer exported.
* **BaseStructType** and **BaseSliceType** removed;  see `sqlx/reflectx` for
  reflect helpers.

The above changes will all be caught by a build step.  The following changes
to *behavior* in sqlx might require significant changes to client code.  If
these are a problem, please vendor the git tag @sqlx-v1.0.

* Non-embedded structs no longer probed for fields as more scan targets.
  This was causing [#60](https://github.com/jmoiron/sqlx/issues/60), but also made little sense.  Embed these structs
  instead.
* `MapScan` and `SliceScan` previously returned values which, while `interface{}`,
  were guaranteed to be a `string` or `nil`.  This guarantee no longer exists,
  as `sql.NullString` and `sql.RawBytes` are *not* safe targets for all types.
  This is related to [#59](https://github.com/jmoiron/sqlx/issues/59), but the problem could pop up in future as well.
* Using the global `NameMapper` to change the behavior of sqlx is discouraged as
  this will no longer impact `sqlx.DB` structs created before the change.

### Going Forward

There is no Go1-like promise of absolute stability, but I take the issue
seriously and will maintain the library in a compatible state unless vital
bugs prevent me from doing so.  Since [#59](https://github.com/jmoiron/sqlx/issues/59) and [#60](https://github.com/jmoiron/sqlx/issues/60) necessitated
breaking behavior, I decided to perform the API cleanup at the same time.

## install

    go get github.com/jmoiron/sqlx

## issues

Row headers can be ambiguous (`SELECT 1 AS a, 2 AS a`), and the result of
`Columns()` can have duplicate names on queries like:

```sql
SELECT a.id, a.name, b.id, b.name FROM foos AS a JOIN foos AS b ON a.parent = b.id;
```

making a struct or map destination ambiguous.  Use `AS` in your queries
to give rows distinct names, `rows.Scan` to scan them manually, or 
`SliceScan` to get a slice of results.

## usage

Below is an example which shows some common use cases for sqlx.  Check 
[sqlx_test.go](https://github.com/jmoiron/sqlx/blob/master/sqlx_test.go) for more
usage.  


```go
package main

import (
    _ "github.com/lib/pq"
    "database/sql"
    "github.com/jmoiron/sqlx"
    "log"
)

var schema = `
CREATE TABLE person (
    first_name text,
    last_name text,
    email text
);

CREATE TABLE place (
    country text,
    city text NULL,
    telcode integer
)`

type Person struct {
    FirstName string `db:"first_name"`
    LastName  string `db:"last_name"`
    Email     string
}

type Place struct {
    Country string
    City    sql.NullString
    TelCode int
}

func main() {
    // this connects & tries a simple 'SELECT 1', panics on error
    // use sqlx.Open() for sql.Open() semantics
    db, err := sqlx.Connect("postgres", "user=foo dbname=bar sslmode=disable")
    if err != nil {
        log.Fatalln(err)
    }

    // exec the schema or fail; multi-statement Exec behavior varies between
    // database drivers;  pq will exec them all, sqlite3 won't, ymmv
    db.MustExec(schema)
    
    tx := db.MustBegin()
    tx.MustExec("INSERT INTO person (first_name, last_name, email) VALUES ($1, $2, $3)", "Jason", "Moiron", "jmoiron@jmoiron.net")
    tx.MustExec("INSERT INTO person (first_name, last_name, email) VALUES ($1, $2, $3)", "John", "Doe", "johndoeDNE@gmail.net")
    tx.MustExec("INSERT INTO place (country, city, telcode) VALUES ($1, $2, $3)", "United States", "New York", "1")
    tx.MustExec("INSERT INTO place (country, telcode) VALUES ($1, $2)", "Hong Kong", "852")
    tx.MustExec("INSERT INTO place (country, telcode) VALUES ($1, $2)", "Singapore", "65")
    // Named queries can use structs, so if you have an existing struct (i.e. person := &Person{}) that you have populated, you can pass it in as &person
    tx.NamedExec("INSERT INTO person (first_name, last_name, email) VALUES (:first_name, :last_name, :email)", &Person{"Jane", "Citizen", "jane.citzen@example.com"})
    tx.Commit()

    // Query the database, storing results in a []Person (wrapped in []interface{})
    people := []Person{}
    db.Select(&people, "SELECT * FROM person ORDER BY first_name ASC")
    jason, john := people[0], people[1]

    fmt.Printf("%#v\n%#v", jason, john)
    // Person{FirstName:"Jason", LastName:"Moiron", Email:"jmoiron@jmoiron.net"}
    // Person{FirstName:"John", LastName:"Doe", Email:"johndoeDNE@gmail.net"}

    // You can also get a single result, a la QueryRow
    jason = Person{}
    err = db.Get(&jason, "SELECT * FROM person WHERE first_name=$1", "Jason")
    fmt.Printf("%#v\n", jason)
    // Person{FirstName:"Jason", LastName:"Moiron", Email:"jmoiron@jmoiron.net"}

    // if you have null fields and use SELECT *, you must use sql.Null* in your struct
    places := []Place{}
    err := db.Select(&places, "SELECT * FROM place ORDER BY telcode ASC")
    if err != nil {
        fmt.Printf(err)
        return
    }
    usa, singsing, honkers = places[0], places[1], places[2]
    
    fmt.Printf("%#v\n%#v\n%#v\n", usa, singsing, honkers)
    // Place{Country:"United States", City:sql.NullString{String:"New York", Valid:true}, TelCode:1}
    // Place{Country:"Singapore", City:sql.NullString{String:"", Valid:false}, TelCode:65}
    // Place{Country:"Hong Kong", City:sql.NullString{String:"", Valid:false}, TelCode:852}

    // Loop through rows using only one struct
    place := Place{}
    rows, err := db.Queryx("SELECT * FROM place")
    for rows.Next() {
        err := rows.StructScan(&place)
        if err != nil {
            log.Fataln(err)
        } 
        fmt.Printf("%#v\n", place)
    }
    // Place{Country:"United States", City:sql.NullString{String:"New York", Valid:true}, TelCode:1}
    // Place{Country:"Hong Kong", City:sql.NullString{String:"", Valid:false}, TelCode:852}
    // Place{Country:"Singapore", City:sql.NullString{String:"", Valid:false}, TelCode:65}

    // Named queries, using `:name` as the bindvar.  Automatic bindvar support
    // which takes into account the dbtype based on the driverName on sqlx.Open/Connect
    _, err = db.NamedExec(`INSERT INTO person (first_name,last_name,email) VALUES (:first,:last,:email)`, 
        map[string]interface{}{
            "first": "Bin",
            "last": "Smuth",
            "email": "bensmith@allblacks.nz",
    })

    // Selects Mr. Smith from the database
    rows, err := db.NamedQuery(`SELECT * FROM person WHERE first_name=:fn`, map[string]interface{}{"fn": "Bin"})

    // Named queries can also use structs.  Their bind names follow the same rules
    // as the name -> db mapping, so struct fields are lowercased and the `db` tag
    // is taken into consideration.
    rows, err := db.NamedQuery(`SELECT * FROM person WHERE first_name=:first_name`, jason)
}
```

## embedded structs

Structs which do not implement the [sql.Scanner](http://golang.org/pkg/database/sql/#Scanner)
interface will be inspected and their fields used as possible targets for a scan.  This includes
embedded and non-embedded structs.

Go makes '[ambiguous selectors](http://play.golang.org/p/MGRxdjLaUc)' a compile time error,
but does not make structs with possible ambiguous selectors errors.  Sqlx will decide
which field to use on a struct based on a breadth first search of the struct and any
structs it contains or embeds, as specified by the order of the fields as accessible
by `reflect`, which generally means in source-order.

## scan safety

By default, scanning into structs requires the structs to have fields for all of the
columns in the query.  This was done for a few reasons:

* A mistake in naming during development could lead you to believe that data is
  being written to a field when actually it can't be found and it is being dropped
* This behavior mirrors the behavior of the Go compiler with respect to unused
  variables
* Selecting more data than you need is wasteful (more data on the wire, more time
  marshalling, etc)

Unlike Marshallers in the stdlib, the programmer scanning an sql result into a struct
will generally have a full understanding of what the underlying data model is *and*
full control over the SQL statement.

Despite this, there are use cases where it's convenient to be able to ignore unknown
columns.  In most of these cases, you might be better off with `ScanSlice`, but where
you want to still use structs, there is now the `Unsafe` method.  Its usage is most
simply shown in an example:

```go
    db, err := sqlx.Connect("postgres", "user=foo dbname=bar sslmode=disable")
    if err != nil {
        log.Fatal(err)
    }

    type Person {
        Name string
    }
    var p Person

    // This fails, because there is no destination for location in Person
    err = db.Get(&p, "SELECT name, location FROM person LIMIT 1")
    
    udb := db.Unsafe()
    
    // This succeeds and just sets `Name` in the p struct
    err = udb.Get(&p, "SELECT name, location FROM person LIMIT 1")
```

The `Unsafe` method is implemented on `Tx`, `DB`, and `Stmt`.  When you use an unsafe
`Tx` or `DB` to create a new `Tx` or `Stmt`, those inherit its lack of safety.

