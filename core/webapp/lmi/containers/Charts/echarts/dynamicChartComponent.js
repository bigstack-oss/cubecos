import React, { Component } from "react";
import { connect } from "react-redux";
import ReactEcharts from "echarts-for-react";
import { updateOption } from "../../../redux/dynamicEchart/reducer";

class DynamicChartComponent extends Component {
	constructor(props) {
		super(props);
		this.fetchNewDate = this.fetchNewDate.bind(this);
		this.count = 0;
	}
	fetchNewDate() {
		this.props.updateOption();
	}
	componentDidMount() {
		if (this.timeTicket) {
			clearInterval(this.timeTicket);
		}
		this.timeTicket = setInterval(this.fetchNewDate, 2500);
	}
	componentWillUnmount() {
		if (this.timeTicket) {
			clearInterval(this.timeTicket);
		}
	}
	render() {
		const option = this.props.option;
		return (
			<div className="examples">
				<ReactEcharts
					ref="echarts_react"
					option={option}
					style={{ height: 300 }}
				/>
			</div>
		);
	}
}

export default connect(
	state => ({
		...state.DynamicChartComponent
	}),
	{ updateOption }
)(DynamicChartComponent);
