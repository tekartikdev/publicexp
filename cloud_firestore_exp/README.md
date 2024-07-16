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