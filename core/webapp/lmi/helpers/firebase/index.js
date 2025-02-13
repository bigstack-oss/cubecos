import firebase from 'firebase';
import ReduxSagaFirebase from 'redux-saga-firebase';
import 'firebase/firestore';
import { firebaseConfig } from '../../config';

const valid =
	firebaseConfig && firebaseConfig.apiKey && firebaseConfig.projectId;

let firebaseApp = {};
let firebaseAuth = {};
try {
	firebaseApp = firebase.initializeApp(firebaseConfig);
	firebaseAuth = firebase.auth;
} catch (e) {}

class FirebaseHelper {
	isValid = valid;
	EMAIL = 'email';
	FACEBOOK = 'facebook';
	GOOGLE = 'google';
	GITHUB = 'github';
	TWITTER = 'twitter';
	constructor() {
		this.login = this.login.bind(this);
		this.logout = this.logout.bind(this);
		this.isAuthenticated = this.isAuthenticated.bind(this);
		this.database = firebase.firestore();
		this.rsf = new ReduxSagaFirebase(firebaseApp, firebase.firestore());
		this.rsfFirestore = this.rsf.firestore;
	}
	createBatch = () => {
		return this.database.batch();
	};
	login(provider, info) {
		switch (provider) {
			case this.EMAIL:
				return firebaseAuth().signInWithEmailAndPassword(
					info.email,
					info.password
				);
			case this.FACEBOOK:
				return firebaseAuth().FacebookAuthProvider();
			case this.GOOGLE:
				return firebaseAuth().GoogleAuthProvider();
			case this.GITHUB:
				return firebaseAuth().GithubAuthProvider();
			case this.TWITTER:
				return firebaseAuth().TwitterAuthProvider();
			default:
		}
	}
	logout() {
		return firebaseAuth().signOut();
	}

	isAuthenticated() {
		firebaseAuth().onAuthStateChanged(user => {
			return user ? true : false;
		});
	}
	resetPassword(email) {
		return firebaseAuth().sendPasswordResetEmail(email);
	}
	createNewRef() {
		return firebase
			.database()
			.ref()
			.push().key;
	}
}

export default new FirebaseHelper();
