export interface Config {
  apiKey: string;
  orgId: string;
  autoTrack?: boolean;
}

export interface Metadata {
  [key: string]: any;
}
export interface Event {
  event_time: Date;
  event_name: string;
  event_data?: Metadata;
  user_id?: string;
  device_id: string;
  session_id?: string;
  device_info?: DeviceInfo;
  location?: LocationInfo;
  id?: string;
}
export interface Identify {
  user_id: string;
  user_data: Metadata;
}

export interface DeviceInfo {
  browser?: {
    name?: string;
    version?: string;
    major?: string;
  };
  os?: {
    name?: string;
    version?: string;
  };
  device?: {
    model?: string;
    type?: string;
    vendor?: string;
  };
  cpu?: {
    architecture?: string;
  };
  engine?: {
    name?: string;
    version?: string;
  };
  ua?: string;
}
export interface LocationInfo {
  latitude?: number;
  longitude?: number;
  accuracy?: number;
  altitude?: number | null;
  altitude_accuracy?: number | null;
  heading?: number | null;
  speed?: number | null;
}
