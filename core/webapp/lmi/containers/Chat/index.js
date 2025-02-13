import React, { Component } from "react";
import { connect } from "react-redux";
import DesktopView from "./desktopView";
import MobileView from "./mobileView";
import { ChatViewWrapper } from "./message.style";

class Chat extends Component {
	render() {
		const { view, height } = this.props;
		const ChatView = view === "MobileView" ? MobileView : DesktopView;
		return (
			<ChatViewWrapper
				style={{ height: view === "MobileView" ? height - 108 : height - 138 }}
			>
				<ChatView height={height} view={view} />
			</ChatViewWrapper>
		);
	}
}
export default connect(state => ({
	...state.App,
	height: state.App.height
}))(Chat);
