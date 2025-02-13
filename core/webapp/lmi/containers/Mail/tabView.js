import React, { Component } from "react";
import { connect } from "react-redux";
import ReactDrawer from "react-motion-drawer";
import { Scrollbars } from "react-custom-scrollbars";
import { InputSearch } from "../../components/uielements/input";
import mailList from "../../components/mail/maiilList";
import mailBuckets from "../../components/mail/mailBuckets";
import mailTags from "../../components/mail/mailTags";
import singleMail from "../../components/mail/singleMail";
import ComposeBtn from "../../components/mail/mailComposeBtn";
import ComposeMail from "../../components/mail/composeMail";
import mailActions from "../../redux/mail/actions";
import PaginationControl from "../../components/mail/mailPagination";
import IntlMessages from "../../components/utility/intlMessages";
import mailSelector from "../../redux/mail/selector";
import MailDrawer from "./mailDrawer.style";
import MailBox from "./mailBox.style";

const {
	filterAction,
	selectMail,
	changeComposeMail,
	changeReplyMail,
	changeSearchString
} = mailActions;

class TabView extends Component {
	constructor(props) {
		super(props);
		this.state = {
			search: this.props.searchString,
			open: false
		};
		this.openDrawer = this.openDrawer.bind(this);
		this.closeDrawer = this.closeDrawer.bind(this);
		this.onDrawerClose = this.onDrawerClose.bind(this);
	}
	openDrawer() {
		this.setState({ open: true });
	}
	closeDrawer() {
		this.setState({ open: false });
	}
	onDrawerClose() {
		this.setState({ open: false });
	}
	onDrawerChange = val => {
		if (!val) {
			this.setState({ open: false });
		}
	};
	render() {
		const {
			allMails,
			filterAttr,
			filterMails,
			selectedMail,
			composeMail,
			replyMail,
			selectMail,
			filterAction,
			changeComposeMail,
			changeReplyMail,
			changeSearchString
		} = this.props;
		const { search } = this.state;
		let singleMailComponent = (
			<p className="isoNoMailMsg">
				<IntlMessages id="email.noMessage" />
			</p>
		);
		const index = allMails.findIndex(mail => mail.id === selectedMail);
		if (index !== -1) {
			singleMailComponent = singleMail(
				allMails,
				filterMails,
				index,
				replyMail,
				changeReplyMail,
				selectMail
			);
		}
		return (
			<div style={{ height: "100%" }}>
				<MailBox className="isomorphicMailBox">
					{composeMail ? (
						""
					) : (
						<div className="isoMiddleWrapper">
							<div className="isoBucketLabel">
								<button className="isoBackCatBtn" onClick={this.openDrawer}>
									<i className="ion-android-menu" />
								</button>
								<h3>{filterAttr.bucket}</h3>
								<PaginationControl />
							</div>
							<div className="isoSearchMailWrapper">
								<InputSearch
									placeholder="Search Email"
									value={search}
									className="isoSearchEmail"
									onChange={event =>
										this.setState({ search: event.target.value })
									}
									onSearch={value => changeSearchString(value)}
								/>
							</div>
							<Scrollbars style={{ height: this.props.height - 70 }}>
								{mailList(filterMails, selectMail, selectedMail)}
							</Scrollbars>
						</div>
					)}
					<div className="isoSingleMailWrapper">
						<Scrollbars style={{ height: this.props.height - 70 }}>
							{composeMail ? (
								<ComposeMail
									allMails={allMails}
									changeComposeMail={changeComposeMail}
									tabView
								/>
							) : (
								singleMailComponent
							)}
						</Scrollbars>
					</div>
				</MailBox>

				<MailDrawer>
					<ReactDrawer
						open={this.state.open}
						right={true}
						onChange={this.onDrawerChange}
					>
						<i onClick={this.closeDrawer} className="icono-cross" />
						<div className="isoLeftWrapper">
							<ComposeBtn
								changeComposeMail={changeComposeMail}
								onDrawerClose={this.onDrawerClose}
							/>
							<div className="isoMailOptions">
								<Scrollbars style={{ height: this.props.height - 70 }}>
									{mailBuckets(
										allMails,
										filterAction,
										filterAttr,
										this.onDrawerClose
									)}
									{mailTags(
										allMails,
										filterAction,
										filterAttr,
										this.onDrawerClose
									)}
								</Scrollbars>
							</div>
						</div>
					</ReactDrawer>
				</MailDrawer>
			</div>
		);
	}
}

function mapStateToProps(state) {
	const {
		allMails,
		tag,
		selectedMail,
		filterAttr,
		composeMail,
		replyMail,
		searchString
	} = state.Mails;
	return {
		allMails,
		tag,
		selectedMail,
		filterAttr,
		composeMail,
		replyMail,
		searchString,
		filterMails: mailSelector(state.Mails)
	};
}
export default connect(mapStateToProps, {
	filterAction,
	selectMail,
	changeComposeMail,
	changeReplyMail,
	changeSearchString
})(TabView);
