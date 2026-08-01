const admin = require("firebase-admin");
admin.initializeApp({
  projectId: "family-tree-app-b64e0"
});
const db = admin.firestore();
db.collectionGroup("events").get().then((snap) => {
  console.log(`Found ${snap.size} events:`);
  snap.forEach((doc) => {
    const data = doc.data();
    console.log({
      id: doc.id,
      title: data.title,
      startDateTime: data.startDateTime ? data.startDateTime.toDate().toISOString() : null,
      createdAt: data.createdAt ? data.createdAt.toDate().toISOString() : null,
      remindersSent: data.remindersSent
    });
  });
  process.exit(0);
}).catch((err) => {
  console.error(err);
  process.exit(1);
});
