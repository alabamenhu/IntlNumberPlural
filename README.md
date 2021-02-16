# IntlNumberPlural
A number to determine the plural count category of a number for use in localization contexts

**Warning:** The name may change in the near-ish future (mid 2021) to be cohesive with other modules. 
If it changes, I will continue to `provide` under the current name for at least one year.

To use:

```raku
use Intl::Number::Plural

                 # English  Arabic  Russian
plural-count 0;  # other    zero    many
plural-count 1;  # one      one     one
plural-count 2;  # other    two     few
plural-count 3;  # other    few     few
plural-count 6;  # other    few     many
```

There are six strings that can be returned by the function: **zero**, **one**, **two**, **few**, **many**, and **other**.
*Other* is the default and is used for all values in languages that do not have grammatical number.
Note that (as evidenced by the above table), the labels don't always correspond to what one might intuitively think.
Consequently, this is a module generally oriented towards makes of localization frameworks, and less so towards end-users.

The `plural-count` sub currently takes one or two positional arguments:

  * **`number`** (required)  
  The number whose count is to be determined.
  * **`from`, `to`**  
  The count is calculated for a range (`from .. to`).
  
There are two optional named parameters

  * **`:language`**  
  The language to be used in determining the count.  Defaults to `user-language`.
  * **`:type`**  
  Acceptable values are **cardinal** and **ordinal**, defaults to *cardinal*.  Some languages behave differently for these two types of numbers.  Ignored for range calculations which always use *cardinal*
  
## Dependencies

  * `Intl::CLDR`  
  Houses the data for calculating the counts
  * `Intl::UserLanguage`  
  Determines the default language when not provided
  
## Todo

  * Use `Intl::CLDR` enums once available.
  * Add tests for major languages

## Version History
  * **v0.5.4**
    * Fixed a small bug (*mod* → *%* for CLDR's *mod*)
  * **v0.5.3**
    * Updated CLDR reference (was `.plurals` in beta, now is `.grammar.plurals`)
  * **v0.5.2**
    * Added support for ranged 
  * **v0.5.1**  
    * Initial release as separate module
  * **v0.1** – **v0.5**  
    * Included as a part of `Intl::CLDR`
  
## License and Copyright

© 2020-2021 Matthew Stephen Stuckwisch.
Licensed under the Artistic License 2.0.