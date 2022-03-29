variable "AWS_ACCESS_KEY" {

}
variable "AWS_SECRET_KEY" {

}

variable "AWS_REGION" {
  default = "eu-west-2"
}


variable "AMIS" {
  type = map(string)
  default = {
  eu-west-2="ami-0b9d3fd1b3ea48792"
  eu-west-1="ami-030768679f07adc54"
  }
}
