# this is to help locate module names
#echo "s/$2 "/###x_add $2 "/"
echo "s/=\s*"$1\.$2"\s/= x_add "$1\.$2" /"
# echo "s/("$1\.$2" /(x_add "$1\.$2" /"
echo "s/(\s*"$1\.$2"\s/(x_add "$1\.$2" /"
# echo "s/= xx_add /= x_add /"
# echo "s/= xxx_add /= x_add /"
# echo "s/= xxxx_add /= x_add /"
# echo "s/(xx_add /(x_add /"
# echo "s/(xxx_add /(x_add /"
# echo "s/(xxxx_add /(x_add /"
#echo "s/("$1\.$2"/#xadd "$1\.$2"/"

