# cloud_firestore_exp

Cloud firestore exp

## To reproduce issue 13019

Run in debug on a web target.

To see the issue on document:
- Setup listener 1
- Setup listener 2
- increment doc => only listener 2 is called

To see the issue on collection:
- Setup listener 3
- Setup listener 4
- increment doc => only listener 4 is called

## Override

To fix the issue, use the following override in your `pubspec.yaml`:

```yaml
  cloud_firestore_web:
    git:
      url: https://github.com/tekartik-2/flutterfire
      path: packages/cloud_firestore/cloud_firestore_web
```

## Additional notes

The smart option used to cancel existing listeners on hot restart
is not really working. listeners are closed by index so the last one is only
disabled when the same index is reached. Instead, all listeners should be closed
on hot restart.

To see that it is not working:

- Setup listener 1
- increment doc => listener 1 is called
- Hot restart
- increment doc => listener 1 is called (and should not)