"Πρώτη ελληνική ιστορία" by Ντινάκος (in Greek)

The time of day is 11:30 pm.

When play begins:
	now the right hand status line είναι "[time of day]";
	now the story viewpoint είναι δεύτερο πληθυντικό πρόσωπο;
	[ now the story tense is μέλλοντας; ]
	say "-123456789 -> [-123456789 in words][line break]";
	say "1000001    -> [1000001 in words][line break]";
	say "8781       -> [8781 in words][line break]";
	say "1234       -> [1234 in words][line break]";
	say "-19        -> [-19 in words][line break]";
	say "Γεια σου!".
	[say "[text of print the final prompt rule response (A)]";]


[ Every turn:
	say "H ώρα είναι [time of day]". ]

[ The carrying capacity of the player is 1. ]

[ A βόλος is a kind of thing. The plural of βόλος is βόλοι.
There are 11 βόλος in the κουζίνα. The description of a βόλος is "Ένα μικρό, σφαιρικό, πολύχρωμο αντικείμενο.". ]

Η κουζίνα (f) είναι ένα δωμάτιο.
[ Υπνοδωμάτιο is a room. Υπνοδωμάτιο είμαι βόρεια της kitchen. ]

the λάμπα (f) is a device in the κουζίνα. the λάμπα is switched off.
[ Η λάμπα (f) είναι συσκευή in the κουζίνα. the λάμπα is switched off. ]

The κρεμάστρα (f) is a στήριγμα in the κουζίνα. The description of the κρεμάστρα is "Μια πλαστική, ξύλινη ή μεταλλική κατασκευή για κρέμασμα ρούχων.".

The απλώστρα (f) is a thing.
There are 2 απλώστρες in the κουζίνα. The description of an απλώστρα is "Μια μεταλλική κατασκευή για να απλώνεις ρούχα.".

The κλόουν (m) is a person. The description of the κλόουν is "Ένας πολύχρωμος κλόουν με μεγάλη μύτη.".
The κλόουν is in the κουζίνα.

Το βιβλίο (n) είναι ένα πράγμα. The description of βιβλίο is "Ένα παλιό βιβλίο με πολλές σελίδες.". The βιβλίο is in the κουζίνα.

[ Instead of switching on the λάμπα:
	say "Κουνάς το διακόπτη, και η λάμπα φέγγει.";
	now the λάμπα is lit.

Instead of switching the λάμπα:
	say "Κουνάς το διακόπτη, και η λάμπα σβήνει.";
	now the λάμπα is unlit. ]

[ The σάκος is an open δοχείο. The σάκος is in the kitchen. ]

A marble is a kind of thing.
έντεκα marbles are in the κουζίνα. The description of a marble is "Ένα μικρό, σφαιρικό, πολύχρωμο αντικείμενο.".

[ Ένας βόλος is a kind of thing.
έντεκα βόλοι are in the kitchen. The description of a βόλος is "Ένα μικρό, σφαιρικό, πολύχρωμο αντικείμενο.". ]

[ A πρέσβης is a kind of thing. 10 πρέσβεις are in the kitchen. ]
[ A πρεσβης is a kind of thing. 10 πρεσβεις are in the kitchen. ]

Ένας μυς is ένα αντικείμενο. 10 μυς are in the κουζίνα.

A χαρακας is ένα πράγμα. 10 χαρακες are in the κουζίνα.
[ A ΧΑΡΑΚΑΣ is a kind of thing. 10 ΧΑΡΑΚΕΣ are in the kitchen. ]

A library is a thing. Understand "βιβλιοθήκη" as a library.
A library is in the kitchen. The library is fixed in place.

A gem is a kind of thing. Understand "διαμάντι" as a gem.
A gem has a text called the χρώμα. Understand the χρώμα property as describing a gem.
The description of a gem είναι usually "The διαμάντι is [χρώμα]."


The ρουμπίνι is a gem in the kitchen. The χρώμα is "κόκκινο".
The emerald is a gem in the kitchen. The χρώμα is "πράσινο".


The player κρατάει ένα νόμισμα (n).
The player κρατάει μία τράπουλα (f).
The player κρατάει δέκα τσιπ.
[ The indefinite article of the νόμισμα is "ένα". ]
The description of the νόμισμα is "[A νόμισμα] έχει ένα ελληνικό άρθρο."

[ TODO: Create a complete testing scenario ]
test me with "οχ/,/τέλος/π/ο/λ,ν/β/βορεια/βόρεια/πάρε βββ"

[ test responses with "" ]