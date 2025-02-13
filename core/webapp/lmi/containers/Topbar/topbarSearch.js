import React, { Component } from "react";
import { connect } from "react-redux";
import { InputSearch } from "../../components/uielements/input";
import TopbarSearchModal from "./topbarSearchModal.style";

class Searchbar extends Component {
	componentDidMount() {
		setTimeout(() => {
			try {
				document.getElementById("InputTopbarSearch").focus();
			} catch (e) {}
		}, 200);
	}
	render() {
		return (
			<InputSearch
				id="InputTopbarSearch"
				size="large"
				placeholder="Enter search text"
				onBlur={this.props.onBlur}
			/>
		);
	}
}

class TopbarSearch extends Component {
	state = {
		visiblity: false
	};
	handleCancel = () => {
		this.setState({
			visible: false
		});
	};
	handleBlur = () => {
		setTimeout(() => {
			this.setState({
				visible: false
			});
		}, 200);
	};
	showModal = () => {
		this.setState({
			visible: true
		});
	};
	render() {
		const { customizedTheme } = this.props;
		const { visible } = this.state;
		return (
			<div onClick={this.showModal}>
				<i
					className="ion-ios-search-strong"
					style={{ color: customizedTheme.textColor }}
				/>
				<TopbarSearchModal
					visible={visible}
					onOk={this.handleCancel}
					onCancel={this.handleCancel}
					wrapClassName="isoSearchModal"
					width="60%"
					footer={null}
				>
					<div className="isoSearchContainer">
						{visible ? <Searchbar onBlur={this.handleBlur} /> : ""}
					</div>
				</TopbarSearchModal>
			</div>
		);
	}
}

export default connect(state => ({
	...state.App,
	customizedTheme: state.ThemeSwitcher.topbarTheme
}))(TopbarSearch);
