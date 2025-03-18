const admin = require('firebase-admin');

// Initialize Firebase Admin with your service account
const serviceAccount = require('./firebase.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function testNotification() {
    try {
        // Test FCM token
        const fcmToken = 'dRRhf3ClQS3rNi7v3VP3RE:APA91bFIuQFbLLjqAJ25_2BFeA9CmHeZZubj_B5Iz9YPmiKPffbHiYesu-Hgi0NpBjGJbbzJFEa489YOTpptBJWPkCz_jXcwNjro--skFM17IXmmvJWOpNw';
        
        // Test message
        const message = {
            notification: {
                title: 'Test Notification',
                body: 'Hello from local test!'
            },
            token: fcmToken
        };

        console.log('Sending test notification...');
        const response = await admin.messaging().send(message);
        console.log('Successfully sent notification:', response);

    } catch (error) {
        console.error('Error sending notification:', error);
    } finally {
        process.exit(0);
    }
}

// Run the test
testNotification(); 