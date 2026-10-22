# Contributing

Bug reports and suggestions are welcome as [issues](https://github.com/degiorgig/pinxel/issues).

## Pull requests

The [license](LICENSE) does not allow changes to Pinxel. As an exception, you may fork the repository and
change the source code only to propose those changes to this repository as a pull request.

By opening a pull request you agree that:

1. the contribution is your own work, or you have the right to submit it;
2. you grant Giovanni Degiorgi a perpetual, worldwide, non-exclusive, royalty-free and irrevocable license to
   use, copy, modify, distribute and sublicense the contribution, under any terms, including the PolyForm
   Strict License and paid commercial licenses;
3. the contribution is provided "as is", without warranty.

You keep the copyright of your contribution.

## Before opening a pull request

- Package tests: `cd PinxelKit && swift test` (on Xcode 26 or earlier: `xcodebuild test -scheme PinxelKit-Package -destination 'platform=macOS'`).
- Every user-facing string goes through the String Catalogs, with English, Italian, German and French
  translations (`python3 scripts/l10n/xcstrings.py coverage <derived data> .` must report nothing missing).
- Code, comments and commit messages are in English.
