const admin = require('firebase-admin');

// Initialize Firebase Admin with your service account
const serviceAccount = require('./firebase.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

exports.handler = async (event) => {
    try {
        // Add CORS headers
        const headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Content-Type': 'application/json'
        };

        // Handle preflight requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers,
                body: ''
            };
        }

        // Parse the message data from the event
        const message = JSON.parse(event.body);
        console.log('Received message:', message); // Debug log
        
        // Get recipient's FCM token from Firestore
        const userDoc = await admin.firestore()
            .collection('users')
            .doc(message.recipientId)
            .get();
            
        if (!userDoc.exists) {
            console.log('User document not found'); // Debug log
            return {
                statusCode: 404,
                headers,
                body: JSON.stringify({ 
                    message: 'User not found',
                    recipientId: message.recipientId 
                })
            };
        }

        const userData = userDoc.data();
        const fcmToken = userData?.fcmToken;
        
        if (!fcmToken) {
            console.log('FCM token not found'); // Debug log
            return {
                statusCode: 404,
                headers,
                body: JSON.stringify({ 
                    message: 'FCM token not found',
                    userData: userData 
                })
            };
        }

        // Send notification via FCM
        await admin.messaging().send({
            notification: {
                title: 'New Message',
                body: message.content
            },
            token: fcmToken
        });
        
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({ 
                message: 'Notification sent successfully',
                recipientId: message.recipientId
            })
        };
        
    } catch (error) {
        console.error('Lambda Error:', error); // Debug log
        return {
            statusCode: 500,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ 
                error: error.message,
                stack: error.stack 
            })
        };
    }
};