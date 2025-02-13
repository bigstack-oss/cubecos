import React, { Component } from "react";
import Link from "next/link";
import { connect } from "react-redux";
import Popover from "../uielements/popover";
import TopbarDropdownWrapper from "./topbarDropdown.style";

const demoMails = [
	{
		id: 1,
		name: "David Doe",
		time: "3 minutes ago",
		desc:
			"A National Book Award Finalist An Edgar Award Finalist A California Book Award Gold Medal Winner"
	},
	{
		id: 2,
		name: "Navis Doe",
		time: "4 minutes ago",
		desc:
			"A National Book Award Finalist An Edgar Award Finalist A California Book Award Gold Medal Winner"
	},
	{
		id: 3,
		name: "Emanual Doe",
		time: "5 minutes ago",
		desc:
			"A National Book Award Finalist An Edgar Award Finalist A California Book Award Gold Medal Winner"
	},
	{
		id: 4,
		name: "Dowain Doe",
		time: "6 minutes ago",
		desc:
			"A National Book Award Finalist An Edgar Award Finalist A California Book Award Gold Medal Winner"
	}
];

class TopbarMail extends Component {
	state = {
		visible: false
	};
	hide = () => {
		this.setState({ visible: false });
	};
	handleVisibleChange = () => {
		this.setState({ visible: !this.state.visible });
	};
	render() {
		const { url, customizedTheme } = this.props;

		const content = (
			<TopbarDropdownWrapper className="topbarMail">
				<div className="isoDropdownHeader">
					<h3>Email</h3>
				</div>
				<div className="isoDropdownBody">
					{demoMails.map(mail => (
						<Link href={`${url}/mailbox`} key={mail.id}>
							<div className="isoDropdownListItem">
								<div className="isoListHead">
									<h5>{mail.name}</h5>
									<span className="isoDate">{mail.time}</span>
								</div>
								<p>{mail.desc}</p>
							</div>
						</Link>
					))}
				</div>
				<a className="isoViewAllBtn">View All</a>
			</TopbarDropdownWrapper>
		);
		return (
			<Popover
				content={content}
				trigger="click"
				visible={this.state.visible}
				onVisibleChange={this.handleVisibleChange}
				placement="bottomLeft"
			>
				<div className="isoIconWrapper">
					<i
						className="ion-email"
						style={{ color: customizedTheme.textColor }}
					/>
					<span>{demoMails.length}</span>
				</div>
			</Popover>
		);
	}
}

export default connect(state => ({
	...state.App,
	customizedTheme: state.ThemeSwitcher.topbarTheme
}))(TopbarMail);
