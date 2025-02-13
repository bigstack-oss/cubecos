import React, { Component } from 'react';

const PendingPool = {};
const ReadyPool = {};

export default class ImageCell extends Component {
  constructor(props) {
    super(props);
    this.loadImage = this.loadImage.bind(this);
    this.onLoadImage = this.onLoadImage.bind(this);
    this.state = {
      ready: false,
    }
  }
  componentWillMount() {
    this.loadImage(this.props.src);
  }
  componentWillReceiveProps(nextProps) {
    if (nextProps.src !== this.props.src) {
      this.setState({src: null});
      this.loadImage(nextProps.src);
    }
  }
  loadImage(src) {
    if (ReadyPool[src]) {
      this.setState({src: src});
      return;
    }

    if (PendingPool[src]) {
      PendingPool[src].push(this.onLoadImage);
      return;
    }
    PendingPool[src] = [this.onLoadImage];

    const img = new Image();
    img.onload = () => {
      PendingPool[src].forEach(callback => {
        callback(src);
      });
      delete PendingPool[src];
      img.onload = null;
      src = undefined;
    };
    img.src = src;
  }
  onLoadImage(src) {
    ReadyPool[src] = true;
    if (src === this.props.src) {
      this.setState({
        src: src,
      });
    }
  }
  render() {
    const style = this.state.src ? {
      backgroundImage : `url(${this.state.src})`,
      width: '80%',
      height: '80%',
      backgroundSize: 'cover',
    } : undefined;
    return <div className="exampleImage" style={style} />;
  }
};
