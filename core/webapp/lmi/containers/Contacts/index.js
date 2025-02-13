import React, { Component } from "react";
import { connect } from "react-redux";
import contactAction from "../../redux/contacts/actions";
import { Layout, Icon } from "antd";
import Button from "../../components/uielements/button";
import ContactList from "../../components/contacts/contactList";
import SingleContactView from "../../components/contacts/singleView";
import EditContactView from "../../components/contacts/editView";
import DeleteButton from "../../components/contacts/deleteButton";
import { otherAttributes } from "./fakeData";
import IntlMessages from "../../components/utility/intlMessages";
import { ContactsWrapper } from "./contacts.style";
import Scrollbar from "../../components/utility/customScrollBar.js";

const {
	changeContact,
	addContact,
	editContact,
	deleteContact,
	viewChange
} = contactAction;

const { Sider, Content } = Layout;
class Contacts extends Component {
	render() {
		const {
			contacts,
			seectedId,
			editView,
			changeContact,
			addContact,
			editContact,
			deleteContact,
			viewChange
		} = this.props;
		const selectedContact = seectedId
			? contacts.filter(contact => contact.id === seectedId)[0]
			: null;
		const onVIewChange = () => viewChange(!editView);
		return (
			<ContactsWrapper
				className="isomorphicContacts"
				style={{ background: "none" }}
			>
				<Sider width="300" className="isoContactListBar">
					<ContactList
						contacts={contacts}
						seectedId={seectedId}
						changeContact={changeContact}
						deleteContact={deleteContact}
					/>
				</Sider>
				<Layout className="isoContactBoxWrapper">
					{selectedContact ? (
						<Content className="isoContactBox">
							<div className="isoContactControl">
								<Button type="button" onClick={onVIewChange}>
									{editView ? <Icon type="check" /> : <Icon type="edit" />}{" "}
								</Button>
								<DeleteButton
									deleteContact={deleteContact}
									contact={selectedContact}
								/>
								<Button
									type="primary"
									onClick={addContact}
									className="isoAddContactBtn"
								>
									<IntlMessages id="contactlist.addNewContact" />
								</Button>
							</div>

							<Scrollbar className="contactBoxScrollbar">
								{editView ? (
									<EditContactView
										contact={selectedContact}
										editContact={editContact}
										otherAttributes={otherAttributes}
									/>
								) : (
									<SingleContactView
										contact={selectedContact}
										otherAttributes={otherAttributes}
									/>
								)}
							</Scrollbar>
						</Content>
					) : (
						<div className="isoContactControl">
							<Button
								type="primary"
								onClick={addContact}
								className="isoAddContactBtn"
							>
								<IntlMessages id="contactlist.addNewContact" />
							</Button>
						</div>
					)}
				</Layout>
			</ContactsWrapper>
		);
	}
}

function mapStateToProps(state) {
	const { contacts, seectedId, editView } = state.Contacts;
	return {
		contacts,
		seectedId,
		editView
	};
}
export default connect(mapStateToProps, {
	changeContact,
	addContact,
	editContact,
	deleteContact,
	viewChange
})(Contacts);
