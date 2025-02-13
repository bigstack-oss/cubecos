import { contacts } from "./reducer";

function ascendingSort(contact1, contact2) {
	const name1 = contact1.name ? contact1.name.toUpperCase() : "~";
	const name2 = contact2.name ? contact2.name.toUpperCase() : "~";
	return name1 > name2 ? 1 : name1 === name2 ? 0 : -1;
}

const contactActions = {
	ADD_CONTACT: "ADD_CONTACT",
	EDIT_CONTACT: "EDIT_CONTACT",
	DELETE__CONTACT: "DELETE__CONTACT",
	CHANGE_CONTACT: "CHANGE_CONTACT",
	EDIT_VIEW: "EDIT_VIEW",
	changeContact: id => ({
		type: contactActions.CHANGE_CONTACT,
		id
	}),
	addContact: () => {
		const newContact = {
			id: new Date(),
			firstName: "",
			avatar: contacts[new Date() % 10].avatar,
			LastName: "",
			mobile: "",
			home: "",
			name: "",
			company: "",
			work: "",
			note: ""
		};
		return (dispatch, getState) => {
			dispatch({
				type: contactActions.ADD_CONTACT,
				contacts: [...getState().Contacts.contacts, newContact],
				selectedId: newContact.id
			});
		};
	},
	editContact: newContact => {
		return (dispatch, getState) => {
			const contacts = getState().Contacts.contacts;
			const newContacts = [];
			contacts.forEach(contact => {
				if (contact.id === newContact.id) {
					newContacts.push(newContact);
				} else {
					newContacts.push(contact);
				}
			});
			dispatch({
				type: contactActions.EDIT_CONTACT,
				contacts: newContacts.sort(ascendingSort)
			});
		};
	},
	deleteContact: id => {
		return (dispatch, getState) => {
			const contacts = getState().Contacts.contacts;
			const seectedId = getState().Contacts.seectedId;
			const newContacts = [];
			contacts.forEach(contact => {
				if (contact.id === id) {
				} else {
					newContacts.push(contact);
				}
			});
			dispatch({
				type: contactActions.DELETE__CONTACT,
				contacts: newContacts,
				seectedId: id === seectedId ? undefined : seectedId
			});
		};
	},
	viewChange: view => ({
		type: contactActions.EDIT_VIEW,
		view
	})
};
export default contactActions;
